"""Map-agnostic dungeon discovery + calibration.

Handles both WDT layouts: ADT-tiled maps (MAID -> per-tile obj files with
MODF/MDDF, like Deadmines/Shadowfang) and global-WMO maps (MODF straight
in the WDT, no tiles, like Ragefire Chasm / Wailing Caverns).

The world -> scene transform is the same empirically self-verifying brute
force as build_placements.py: the candidate 2D map that puts the most
AzerothCore creature spawns inside the main WMO's group boxes wins, and
the hit rate is the health metric.
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


def load_spawns(ac_map):
    rows = []
    pat = re.compile(r"^\((\d+), ?(\d+), ?\d+, ?\d+, ?%d, ?" % ac_map)
    for line in (AC / "creature.sql").read_text(encoding="utf-8").splitlines():
        m = pat.match(line)
        if not m:
            continue
        f = line.strip("(),;").split(",")
        rows.append({"guid": int(f[0]), "entry": int(f[1]),
                     "x": float(f[10]), "y": float(f[11]),
                     "z": float(f[12]), "o": float(f[13])})
    return rows


def entrance(ac_map):
    """areatrigger_teleport row targeting this map -> (x, y, z, o) or None."""
    path = AC / "areatrigger_teleport.sql"
    if not path.exists():
        return None
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.startswith("("):
            continue
        # (ID, 'Name', target_map, x, y, z, o),
        m = re.match(r"^\(\d+, ?'(?:[^'\\]|\\.)*', ?(\d+), ?"
                     r"(-?[\d.]+), ?(-?[\d.]+), ?(-?[\d.]+), ?(-?[\d.]+)",
                     line)
        if m and int(m.group(1)) == ac_map:
            return (float(m.group(2)), float(m.group(3)),
                    float(m.group(4)), float(m.group(5)))
    return None


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
            seen[uid] = {"fdid": nid, "pos": pos, "rot": rot}

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
    if all(abs(v) < 0.01 for v in main_pl["pos"]) \
            and all(abs(v) < 0.01 for v in main_pl["rot"]):
        # global-WMO map: the WMO is authored at the world origin, so server
        # coords map straight into WMO-local space (no file-coord shift)
        ox, oy, oz = 0.0, 0.0, 0.0
        ry_main = 0.0
    else:
        ox, oy, oz = world_from_file(*main_pl["pos"])
        ry_main = main_pl["rot"][1]
    root = roots[main_pl["fdid"]]
    boxes = [g["bbox"] for g in root.group_names]

    def inside(xl, yl, zl, margin=8.0):
        for b in boxes:
            if (min(b[0], b[3]) - margin <= xl <= max(b[0], b[3]) + margin
                    and min(b[1], b[4]) - margin <= yl <= max(b[1], b[4]) + margin
                    and min(b[2], b[5]) - margin <= zl <= max(b[2], b[5]) + margin):
                return True
        return False

    best = None
    for deg in (ry_main, ry_main - 270, ry_main - 180, ry_main - 90,
                -ry_main, 270 - ry_main, 90 - ry_main, 180 - ry_main):
        th = math.radians(deg)
        c_, s_ = math.cos(th), math.sin(th)
        for mat in ([[c_, -s_], [s_, c_]], [[c_, s_], [-s_, c_]],
                    [[c_, s_], [s_, -c_]], [[-c_, s_], [s_, c_]]):
            hits = 0
            for sp in spawns:
                dn, dw = sp["x"] - ox, sp["y"] - oy
                xl = mat[0][0] * dn + mat[0][1] * dw
                yl = mat[1][0] * dn + mat[1][1] * dw
                if inside(xl, yl, sp["z"] - oz):
                    hits += 1
            if best is None or hits > best[0]:
                best = (hits, deg, mat)
    hits, deg, mat = best
    det = mat[0][0] * mat[1][1] - mat[0][1] * mat[1][0]
    return {"origin": (ox, oy, oz), "mat": mat, "ry_main": ry_main,
            "det": det, "hits": hits, "total": len(spawns)}


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
