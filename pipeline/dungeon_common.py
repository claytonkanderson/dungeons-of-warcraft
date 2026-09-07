"""Map-agnostic dungeon discovery + calibration.

Handles both WDT layouts: ADT-tiled maps (MAID -> per-tile obj files with
MODF/MDDF, like Deadmines/Shadowfang) and global-WMO maps (MODF straight
in the WDT, no tiles, like Ragefire Chasm / Wailing Caverns).

The world -> scene transform is found by brute force over 32 candidate
frames: the one that puts the most AzerothCore creature spawns inside the
placed WMOs' group boxes wins, and the hit rate is the health metric. When
spawns cannot separate candidates (an outdoor map with dozens of loose
buildings), the world-space box each MODF placement records breaks the tie:
the right frame reproduces those boxes from the buildings' local geometry.
"""
import math
import re
import struct

from config import AC
from wmo import WMORoot, chunks_of
from gltf_export import YARD

MAP_CENTER = 32 * 533.33333


def world_from_file(fx, fy, fz):
    return (MAP_CENTER - fz, MAP_CENTER - fx, fy)


def find_wdt(s, map_name):
    return s.root.fdid_for_path(f"world/maps/{map_name}/{map_name}.wdt")


def sql_columns(path):
    """Column names of a mysqldump table, in order, from its CREATE TABLE.

    AzerothCore reshapes these tables between releases — creature_template
    went from 61 columns to 55 — so anything read by a hardcoded position
    silently lands on the wrong field. Callers look indices up by name."""
    txt = path.read_text(encoding="utf-8", errors="replace")
    m = re.search(r"CREATE TABLE[^;]*?\((.*?)\)\s*ENGINE", txt, re.S)
    if not m:
        raise RuntimeError(f"{path.name}: no CREATE TABLE to read columns from")
    return re.findall(r"^\s*`([A-Za-z0-9_]+)`", m.group(1), re.M)


# Spawns on an instance map that are not part of the dungeon: seasonal event
# NPCs (Love is in the Air runs its boss fight inside Shadowfang Keep),
# [DND] script helpers, invisible trigger units, and a second copy of a boss
# used by a scripted event. They rarely export a model, but they still count
# toward the XP budget and the roster, so they are dropped at the source.
JUNK_SPAWN = re.compile(r"\[DND\]|Invisible Stalker|Apothecary Hummel"
                        r"|Crown Apothecary|Crazed Apothecary|Vial Bunny"
                        r"|Fezzen Brasstacks|^Arugal$")


def creature_names():
    """entry -> name from creature_template (name is column 6 in every
    AzerothCore layout seen so far; checked against the CREATE TABLE)."""
    cols = sql_columns(AC / "creature_template.sql")
    idx = cols.index("name")
    names = {}
    pat = re.compile(r"^\((\d+),")
    for line in (AC / "creature_template.sql").read_text(
            encoding="utf-8", errors="replace").splitlines():
        m = pat.match(line)
        if not m:
            continue
        # walk to the name column respecting quotes
        f, buf, i, q = [], [], 1, False
        while i < len(line) and len(f) <= idx:
            c = line[i]
            if q:
                if c == "\\":
                    buf.append(line[i + 1]); i += 2; continue
                if c == "'":
                    q = False
                else:
                    buf.append(c)
            elif c == "'":
                q = True
            elif c in ",)":
                f.append("".join(buf)); buf = []
            else:
                buf.append(c)
            i += 1
        if len(f) > idx:
            names[int(m.group(1))] = f[idx]
    return names


def in_bounds(b, x, y, z):
    """`bounds`: a dict of xmin/xmax/ymin/ymax/zmin/zmax in server world
    coordinates, any subset; the part of one map that is one instance."""
    if not b:
        return True
    return (x >= b.get("xmin", -1e9) and x <= b.get("xmax", 1e9)
            and y >= b.get("ymin", -1e9) and y <= b.get("ymax", 1e9)
            and z >= b.get("zmin", -1e9) and z <= b.get("zmax", 1e9))


def load_spawns(ac_map, wing=None, bounds=None, extra=None):
    """Creature spawns on the map; with `wing`, only that wing's (see
    wing_keep); with `bounds`, only those inside (see in_bounds). `extra`:
    [(name, x, y, z, o)] spawns the rows lack because a script summons the
    creature (a raid's last boss), placed as given, filters not applied."""
    rows = []
    names = creature_names()
    dropped = {}
    pat = re.compile(r"^\((\d+), ?(\d+), ?\d+, ?\d+, ?%d, ?" % ac_map)
    for line in (AC / "creature.sql").read_text(encoding="utf-8").splitlines():
        m = pat.match(line)
        if not m:
            continue
        f = line.strip("(),;").split(",")
        entry = int(f[1])
        nm = names.get(entry, "")
        if JUNK_SPAWN.search(nm):
            dropped[nm] = dropped.get(nm, 0) + 1
            continue
        rows.append({"guid": int(f[0]), "entry": entry,
                     "x": float(f[10]), "y": float(f[11]),
                     "z": float(f[12]), "o": float(f[13])})
    if dropped:
        print("non-dungeon spawns dropped: " + ", ".join(
            f"{n} x{c}" for n, c in sorted(dropped.items())))
    if wing:
        keep = wing_keep(ac_map, wing)
        before = len(rows)
        rows = [r for r in rows if keep(r["x"], r["y"])]
        print(f"wing {wing}: {len(rows)} of {before} spawns")
    if bounds:
        before = len(rows)
        rows = [r for r in rows if in_bounds(bounds, r["x"], r["y"], r["z"])]
        print(f"bounds {bounds}: {len(rows)} of {before} spawns")
    for i, (name, x, y, z, o) in enumerate(extra or []):
        entry = next((e for e, n in names.items() if n == name), None)
        if entry is None:
            print(f"!! extra spawn {name!r}: no creature_template row (re-run trim_ac.py)")
            continue
        rows.append({"guid": -1 - i, "entry": entry, "x": float(x), "y": float(y),
                     "z": float(z), "o": float(o)})
        print(f"extra spawn: {name} (entry {entry}) at ({x}, {y}, {z})")
    return rows


def entrances(ac_map):
    """Every areatrigger_teleport row targeting this map, in file order:
    [(name, x, y, z, o)]. A map with several wings (Scarlet Monastery) has
    one per wing, named "<Dungeon> - <Wing> (Entrance)"."""
    path = AC / "areatrigger_teleport.sql"
    out = []
    if not path.exists():
        return out
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.startswith("("):
            continue
        # (ID, 'Name', target_map, x, y, z, o),
        m = re.match(r"^\(\d+, ?'((?:[^'\\]|\\.)*)', ?(\d+), ?"
                     r"(-?[\d.]+), ?(-?[\d.]+), ?(-?[\d.]+), ?(-?[\d.]+)",
                     line)
        if m and int(m.group(2)) == ac_map:
            out.append((m.group(1).replace("\\'", "'"),
                        float(m.group(3)), float(m.group(4)),
                        float(m.group(5)), float(m.group(6))))
    return out


def entrance(ac_map, wing=None, name_part=None):
    """The map's entrance trigger -> (x, y, z, o) or None. With `wing` or
    `name_part`, the first trigger whose name carries it; else the first
    row for the map."""
    want = name_part or wing
    for name, x, y, z, o in entrances(ac_map):
        if want is None or want.lower() in name.lower():
            return (x, y, z, o)
    return None


def wing_keep(ac_map, wing):
    """A predicate keep(x, y) over server world coordinates: true when the
    nearest of the map's entrance triggers is the wing's own. The wings of a
    multi-instance map are separate buildings stood far apart on one map,
    each with its own entrance trigger, so nearest-entrance partitions
    everything on the map (creatures, gameobjects, props, tiles). The
    calibration hit rate after the split is the check that it held."""
    ents = entrances(ac_map)
    mine = [(e[1], e[2]) for e in ents if wing.lower() in e[0].lower()]
    if not mine:
        raise SystemExit(
            "wing %r matches no entrance trigger on map %d: %s"
            % (wing, ac_map, ", ".join(e[0] for e in ents)))
    others = [(e[1], e[2]) for e in ents if wing.lower() not in e[0].lower()]

    def keep(x, y):
        d = min((x - mx) ** 2 + (y - my) ** 2 for mx, my in mine)
        return all(d <= (x - ox) ** 2 + (y - oy) ** 2 for ox, oy in others)
    return keep


def wmo_placements(s, wdt_fdid):
    """uid -> {fdid, pos, rot} from either WDT layout, plus tile obj fdids."""
    c = chunks_of(s.read_fdid(wdt_fdid))
    flags = struct.unpack_from("<I", c.get(b"MPHD", bytes(4)), 0)[0]
    seen = {}
    obj_fdids = []

    def read_modf(modf):
        for k in range(len(modf) // 64):
            nid, uid = struct.unpack_from("<II", modf, k * 64)
            pos = struct.unpack_from("<3f", modf, k * 64 + 8)
            rot = struct.unpack_from("<3f", modf, k * 64 + 20)
            bounds = struct.unpack_from("<6f", modf, k * 64 + 32)   # world AABB
            seen[uid] = {"fdid": nid, "pos": pos, "rot": rot, "bounds": bounds}

    if flags & 0x1:                       # global-WMO map: MODF in the WDT
        read_modf(c.get(b"MODF", b""))
        return seen, obj_fdids, flags
    main, maid = c[b"MAIN"], c[b"MAID"]
    for i in range(64 * 64):
        if not int.from_bytes(main[i * 8:i * 8 + 4], "little") & 1:
            continue
        e = struct.unpack_from("<8I", maid, i * 32)
        obj_fdids.append(e[1])
        oc = chunks_of(s.read_fdid(e[1]))
        read_modf(oc.get(b"MODF", b""))
    return seen, obj_fdids, flags


def pick_main(s, placements):
    """The placement whose WMO has the most groups anchors the scene."""
    best = None
    roots = {}
    for uid, p in placements.items():
        fdid = p["fdid"]
        if fdid not in roots:
            try:
                roots[fdid] = WMORoot(s.read_fdid(fdid))
            except Exception:
                continue
        n = len(roots[fdid].group_names)
        if best is None or n > best[0]:
            best = (n, uid)
    return best[1], roots


def calibrate(s, spawns, placements, main_uid, roots):
    main_pl = placements[main_uid]
    global_wmo = all(abs(v) < 0.01 for v in main_pl["pos"])
    if global_wmo:
        # global-WMO map: the WMO is authored at the world origin, so server
        # coords map straight into WMO-local space (no file-coord shift). It
        # may still be placed turned (Dire Maul: 180 degrees), which the
        # candidate rotations below absorb through ry_main
        ox, oy, oz = 0.0, 0.0, 0.0
    else:
        ox, oy, oz = world_from_file(*main_pl["pos"])
    ry_main = main_pl["rot"][1]

    # Every placed WMO votes, not just the main one: an outdoor map (Zul'Farrak)
    # keeps its spawns in dozens of small buildings and none in the largest,
    # and a candidate frame that is wrong leaves every building's yaw wrong
    # against the positions it stands among.
    frames = []
    for uid, p in placements.items():
        root = roots.get(p["fdid"])
        if root is None:
            continue
        if global_wmo:
            if uid != main_uid:
                continue
            origin, ry = (0.0, 0.0, 0.0), ry_main   # its own turn (Dire Maul: 180)
        else:
            origin, ry = world_from_file(*p["pos"]), p["rot"][1]
        boxes = [g["bbox"] for g in root.group_names]
        if not boxes:
            continue
        margin = 8.0
        lo = [min(min(b[i], b[i + 3]) for b in boxes) - margin for i in range(3)]
        hi = [max(max(b[i], b[i + 3]) for b in boxes) + margin for i in range(3)]
        # the placement's own world-space box, from the MODF entry: the one
        # witness of the building's orientation that spawns cannot give
        wbox = None
        if "bounds" in p:
            b = p["bounds"]
            w0 = world_from_file(b[0], b[1], b[2])
            w1 = world_from_file(b[3], b[4], b[5])
            wbox = ([min(w0[i], w1[i]) for i in range(2)],
                    [max(w0[i], w1[i]) for i in range(2)])
        frames.append((origin, ry, boxes, lo, hi, wbox))

    def inside(boxes, xl, yl, zl, margin=8.0):
        for b in boxes:
            if (min(b[0], b[3]) - margin <= xl <= max(b[0], b[3]) + margin
                    and min(b[1], b[4]) - margin <= yl <= max(b[1], b[4]) + margin
                    and min(b[2], b[5]) - margin <= zl <= max(b[2], b[5]) + margin):
                return True
        return False

    def cand_deg(k, ry):
        return (ry, ry - 270, ry - 180, ry - 90, -ry, 270 - ry, 90 - ry, 180 - ry)[k]

    def forms(deg):
        th = math.radians(deg)
        c_, s_ = math.cos(th), math.sin(th)
        return ([[c_, -s_], [s_, c_]], [[c_, s_], [-s_, c_]],
                [[c_, s_], [s_, -c_]], [[-c_, s_], [s_, c_]])

    def box_error(mats):
        """How far each building's local box, put into the world through the
        candidate frame, lands from the world box its placement records."""
        err = 0.0
        for (origin, _ry, _boxes, lo, hi, wbox), mat in zip(frames, mats):
            if wbox is None:
                continue
            det = mat[0][0] * mat[1][1] - mat[0][1] * mat[1][0]
            if abs(det) < 1e-9:
                continue
            inv = [[mat[1][1] / det, -mat[0][1] / det],
                   [-mat[1][0] / det, mat[0][0] / det]]
            xs, ys = [], []
            for xl in (lo[0] + 8.0, hi[0] - 8.0):       # the margin taken off
                for yl in (lo[1] + 8.0, hi[1] - 8.0):
                    xs.append(origin[0] + inv[0][0] * xl + inv[0][1] * yl)
                    ys.append(origin[1] + inv[1][0] * xl + inv[1][1] * yl)
            err += (abs(min(xs) - wbox[0][0]) + abs(max(xs) - wbox[1][0])
                    + abs(min(ys) - wbox[0][1]) + abs(max(ys) - wbox[1][1]))
        return err

    scores = {}
    for k in range(8):
        for fi in range(4):
            hits = 0
            mats = [forms(cand_deg(k, ry))[fi] for _o, ry, _b, _lo, _hi, _w in frames]
            for sp in spawns:
                for (origin, _ry, boxes, lo, hi, _w), mat in zip(frames, mats):
                    fx, fy, fz = origin
                    dn, dw = sp["x"] - fx, sp["y"] - fy
                    xl = mat[0][0] * dn + mat[0][1] * dw
                    yl = mat[1][0] * dn + mat[1][1] * dw
                    zl = sp["z"] - fz
                    if (lo[0] <= xl <= hi[0] and lo[1] <= yl <= hi[1]
                            and lo[2] <= zl <= hi[2] and inside(boxes, xl, yl, zl)):
                        hits += 1
                        break           # one vote per spawn
            scores[(k, fi)] = (hits, box_error(mats))
    # the spawn vote first; among candidates it cannot separate (many loose
    # buildings on an outdoor map put most spawns inside something under any
    # frame) the placement boxes decide
    top = max(h for h, _e in scores.values())
    eligible = [c for c, (h, _e) in scores.items() if h >= top * 0.9]
    k, fi = min(eligible, key=lambda c: (scores[c][1], c))
    hits, err = scores[(k, fi)]
    deg = cand_deg(k, ry_main)
    mat = forms(deg)[fi]
    det = mat[0][0] * mat[1][1] - mat[0][1] * mat[1][0]
    return {"origin": (ox, oy, oz), "mat": mat, "ry_main": ry_main,
            "det": det, "hits": hits, "total": len(spawns),
            "candidate": (k, fi), "wmos": len(frames), "box_err": err,
            "tied": len(eligible)}


class Transform:
    def __init__(self, cal):
        self.ox, self.oy, self.oz = cal["origin"]
        self.mat = cal["mat"]
        self.ry_main = cal["ry_main"]
        self.sgn = 1.0 if cal["det"] > 0 else -1.0

    def to_local(self, wx, wy, wz):
        dn, dw = wx - self.ox, wy - self.oy
        return (self.mat[0][0] * dn + self.mat[0][1] * dw,
                self.mat[1][0] * dn + self.mat[1][1] * dw, wz - self.oz)

    def to_gl(self, wx, wy, wz):
        p = self.to_local(wx, wy, wz)
        return [-p[1] * YARD, p[2] * YARD, -p[0] * YARD]

    def yaw_of(self, rot_y_deg):
        return self.sgn * math.radians(rot_y_deg - self.ry_main)

    def dir_to_gl_yaw(self, wx, wy):
        xl = self.mat[0][0] * wx + self.mat[0][1] * wy
        yl = self.mat[1][0] * wx + self.mat[1][1] * wy
        gx, gz = -yl, -xl
        return math.atan2(-gx, -gz)
