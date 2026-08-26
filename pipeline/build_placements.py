"""Calibrate world->WMO-local transform and emit placements.json.

World (server) coords: X north, Y west, Z up.  ADT file coords: y up,
center 32*533.333.  The 2D yaw convention is derived empirically: the
candidate that puts the most creature spawns inside the dungeon's group
bounding boxes wins.
"""
import json
import math
import re
import struct
from pathlib import Path

from config import OUT
from casc import Storage, CascError
from wmo import WMORoot, chunks_of
from m2 import M2Model, Skin
from blp import blp_to_png
from gltf_export import YARD, export_static_glb, _cv, _cq

AC = Path(r"D:\tree\azerothcore-wotlk\data\sql\base\db_world")
MAP_CENTER = 32 * 533.33333
MAIN_FDID = 108483
WMO_NAMES = {108483: "deadmines", 108538: "exit", 113966: "wall_tower",
             113970: "wall_solid", 114107: "boat_es01", 114109: "boat_sc2"}


def world_from_file(fx, fy, fz):
    return (MAP_CENTER - fz, MAP_CENTER - fx, fy)


def load_spawns():
    rows = []
    pat = re.compile(r"^\((\d+), ?(\d+), ?\d+, ?\d+, ?36, ?")
    for line in (AC / "creature.sql").read_text(encoding="utf-8").splitlines():
        m = pat.match(line)
        if not m:
            continue
        f = line.strip("(),;").split(",")
        rows.append({"guid": int(f[0]), "entry": int(f[1]),
                     "x": float(f[10]), "y": float(f[11]),
                     "z": float(f[12]), "o": float(f[13])})
    return rows


def wmo_placements(s):
    wdt = s.read_fdid(780605)
    c = chunks_of(wdt)
    main, maid = c[b"MAIN"], c[b"MAID"]
    seen = {}
    for i in range(64 * 64):
        if not int.from_bytes(main[i * 8:i * 8 + 4], "little") & 1:
            continue
        e = struct.unpack_from("<8I", maid, i * 32)
        oc = chunks_of(s.read_fdid(e[1]))
        modf = oc.get(b"MODF", b"")
        for k in range(len(modf) // 64):
            nid, uid = struct.unpack_from("<II", modf, k * 64)
            pos = struct.unpack_from("<3f", modf, k * 64 + 8)
            rot = struct.unpack_from("<3f", modf, k * 64 + 20)
            seen[uid] = {"fdid": nid, "pos": pos, "rot": rot}
    return seen


def main():
    s = Storage()
    spawns = load_spawns()
    print(f"{len(spawns)} creature spawns")
    placements = wmo_placements(s)
    main_pl = next(p for p in placements.values() if p["fdid"] == MAIN_FDID)
    fx, fy, fz = main_pl["pos"]
    ry_main = main_pl["rot"][1]
    ox, oy, oz = world_from_file(fx, fy, fz)  # WMO origin in world coords
    print(f"main WMO world origin ({ox:.1f},{oy:.1f},{oz:.1f}) ry={ry_main}")

    root = WMORoot(s.read_fdid(MAIN_FDID))
    boxes = [g["bbox"] for g in root.group_names]

    def inside(xl, yl, zl, margin=8.0):
        for b in boxes:
            if (min(b[0], b[3]) - margin <= xl <= max(b[0], b[3]) + margin
                    and min(b[1], b[4]) - margin <= yl <= max(b[1], b[4]) + margin
                    and min(b[2], b[5]) - margin <= zl <= max(b[2], b[5]) + margin):
                return True
        return False

    # candidate 2D maps: local_xy = M . (dN, dW), rotations and reflections
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
    print(f"best: {hits}/{len(spawns)} inside, yaw={deg:.1f} deg, det={det:+.2f}")

    def to_local(wx, wy, wz):
        dn, dw = wx - ox, wy - oy
        return (mat[0][0] * dn + mat[0][1] * dw,
                mat[1][0] * dn + mat[1][1] * dw, wz - oz)

    def to_gl(p):  # wow local -> godot/gltf
        return [-p[1] * YARD, p[2] * YARD, -p[0] * YARD]

    def dir_to_gl_yaw(wx, wy):  # facing vector -> gl yaw about +Y
        xl = mat[0][0] * wx + mat[0][1] * wy
        yl = mat[1][0] * wx + mat[1][1] * wy
        # gl forward for yaw a: (-sin a on x? ) — use atan2 on gl axes:
        gx, gz = -yl, -xl
        return math.atan2(-gx, -gz)  # godot node -Z faces (gx,gz)

    vc = next(sp for sp in spawns if sp["entry"] == 639)
    print("VanCleef local:", [round(v, 1) for v in to_local(vc["x"], vc["y"], vc["z"])])

    out = {"wmos": [], "creatures": []}
    sgn = 1.0 if det > 0 else -1.0
    for uid, p in sorted(placements.items()):
        w = world_from_file(*p["pos"])
        loc = to_local(*w)
        name = WMO_NAMES.get(p["fdid"], str(p["fdid"]))
        out["wmos"].append({
            "uid": uid, "fdid": p["fdid"], "glb": f"{name}.glb",
            "pos": to_gl(loc),
            "yaw": sgn * math.radians(p["rot"][1] - ry_main),
        })
    # entrance areatrigger target (map 36)
    ex, ey, ez, eo = -16.4, -383.07, 61.78, 1.86
    out["spawn"] = {"pos": to_gl(to_local(ex, ey, ez)),
                    "yaw": dir_to_gl_yaw(math.cos(eo), math.sin(eo))}
    for sp in spawns:
        out["creatures"].append({
            "guid": sp["guid"], "entry": sp["entry"],
            "pos": to_gl(to_local(sp["x"], sp["y"], sp["z"])),
            "yaw": dir_to_gl_yaw(math.cos(sp["o"]), math.sin(sp["o"])),
        })
    # ---- WMO doodads (positions are in each WMO's local space; parent
    # them to the WMO node in Godot so no extra math is needed)
    out["doodads"] = []
    needed = set()
    for uid, p in sorted(placements.items()):
        if p["fdid"] not in (108483, 108538):
            continue
        r = WMORoot(s.read_fdid(p["fdid"]))
        dset = r.doodad_sets[0] if r.doodad_sets else None
        defs = r.doodad_defs[dset["start"]:dset["start"] + dset["count"]] \
            if dset else r.doodad_defs
        for d in defs:
            if d["index"] >= len(r.doodad_fdids):
                continue
            fdid = r.doodad_fdids[d["index"]]
            if not fdid:
                continue
            needed.add(fdid)
            gp = _cv(d["pos"])
            gq = _cq(d["rot"])
            out["doodads"].append({
                "parent_uid": uid, "fdid": fdid,
                "pos": [gp[0] * YARD, gp[1] * YARD, gp[2] * YARD],
                "quat": list(gq), "scale": d["scale"],
            })

    # ---- tile props (MDDF, world space -> main-WMO local scene space)
    out["props"] = []
    wdt = s.read_fdid(780605)
    c = chunks_of(wdt)
    mainc, maid = c[b"MAIN"], c[b"MAID"]
    for i in range(64 * 64):
        if not int.from_bytes(mainc[i * 8:i * 8 + 4], "little") & 1:
            continue
        e = struct.unpack_from("<8I", maid, i * 32)
        oc = chunks_of(s.read_fdid(e[1]), )
        mddf = oc.get(b"MDDF", b"")
        mmid = oc.get(b"MMID", b"")
        mmdx = oc.get(b"MMDX", b"")
        for k in range(len(mddf) // 36):
            o = k * 36
            nid, uid2 = struct.unpack_from("<II", mddf, o)
            px, py, pz = struct.unpack_from("<3f", mddf, o + 8)
            rx, ryd, rz = struct.unpack_from("<3f", mddf, o + 20)
            sc, mf = struct.unpack_from("<HH", mddf, o + 32)
            if mf & 0x40:
                fdid = nid
            else:
                ofs = struct.unpack_from("<I", mmid, nid * 4)[0]
                nm = mmdx[ofs:mmdx.index(b"\0", ofs)].decode()
                fdid = s.root.fdid_for_path(nm.replace(".mdx", ".m2")
                                              .replace(".MDX", ".m2"))
                if not fdid:
                    continue
            needed.add(fdid)
            w = world_from_file(px, py, pz)
            out["props"].append({
                "fdid": fdid, "pos": to_gl(to_local(*w)),
                "yaw": sgn * math.radians(ryd - ry_main),
                "scale": sc / 1024.0,
            })

    # ---- export unique static models
    dd_dir = OUT / "deadmines" / "doodads"
    dd_dir.mkdir(parents=True, exist_ok=True)
    ok = fail = 0
    for fdid in sorted(needed):
        dest_glb = dd_dir / f"{fdid}.glb"
        if dest_glb.exists():
            ok += 1
            continue
        try:
            m = M2Model(s.read_fdid(fdid))
            if not m.sfid or not m.vertices:
                fail += 1
                continue
            skin = Skin(s.read_fdid(m.sfid[0]))
            texs = {}
            for ti, tex in enumerate(m.textures):
                tf = None
                if tex["type"] == 0:
                    if ti < len(m.txid) and m.txid[ti]:
                        tf = m.txid[ti]
                    elif tex["name"]:
                        tf = s.root.fdid_for_path(tex["name"])
                if tf:
                    try:
                        texs[ti] = blp_to_png(s.read_fdid(tf))
                    except CascError:
                        pass
            export_static_glb(m, skin, texs, dest_glb)
            ok += 1
        except (CascError, KeyError, ValueError) as e:
            print(f"  doodad {fdid}: {e}")
            fail += 1
    print(f"doodad models: {ok} exported, {fail} failed")

    dest = OUT / "deadmines" / "placements.json"
    with open(dest, "w") as f:
        json.dump(out, f, indent=1)
    print("wrote", dest, f"({len(out['wmos'])} wmos, "
          f"{len(out['doodads'])} doodads, {len(out['props'])} props, "
          f"{len(out['creatures'])} creatures)")
    print("spawn gl:", [round(v, 2) for v in out["spawn"]["pos"]])


if __name__ == "__main__":
    main()
