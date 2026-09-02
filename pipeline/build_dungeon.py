"""Build one dungeon end to end: WMOs, doodads, props, placements,
creatures, terrain, ambience.

  python build_dungeon.py --dungeon shadowfang-keep
  python build_dungeon.py --all              # every configured dungeon

Output lands in assets/wow/<dungeon-id>/ in exactly the layout the game
already loads; dungeons.gd marks the entry "built" the moment
placements.json exists.
"""
import argparse
import json
import math
import re
import struct

from config import OUT
from casc import Storage, CascError
from wmo import WMORoot, chunks_of
from m2 import M2Model, Skin
from blp import blp_to_png
from gltf_export import YARD, export_static_glb, _cv, _cq
from extract_deadmines import extract_wmo
import build_creatures
import build_terrain
from dungeon_common import (find_wdt, load_spawns, entrance, wmo_placements,
                            pick_main, calibrate, Transform, world_from_file)
from dungeon_config import DUNGEONS

# WoW scatters barrels and crates by the hundred as filler. Dropped in from
# a Diablo camera they read as clutter rather than set dressing, so they are
# neither exported nor placed.
#
# Model names are CamelCase with no separators, so a bare substring search is
# wrong: "urn" hides inside "BurnedGypsywagon" and "ButterChurner", both of
# which are set pieces. A clutter word therefore has to start a CamelCase
# token, or sit at the start of the name or after a separator.
CLUTTER = re.compile(r"(?:^|[^A-Za-z])(?:barrel|crate|urn|jug|basket|vase)"
                     r"|Barrel|Crate|Urn|Jug|Basket|Vase")

# WoW builds smoke, steam and fog out of particle emitters. The emitter's own
# *mesh* is just a bounding cuboid — the visuals live in emitter data we do
# not export — so drawn as ordinary geometry it becomes a house-sized black
# and white box sitting in the middle of the room.
#
# Two patterns, because name alone cannot tell them apart. Nothing called an
# emitter or embers is ever real geometry, so those go unconditionally. The
# rest of the vocabulary is shared with solid props: the Deadmines steam
# gauges and whistles are set dressing on the machinery. Those are separated
# by the mesh itself — a placeholder is a bare 24-vertex cuboid metres across,
# where the gauges carry 154 vertices inside a third of a metre.
EFFECT_ALWAYS = re.compile(r"emitter|ember", re.I)
EFFECT_BOXY = re.compile(r"steam|smoke|geyser|fog|dust|sparkle|glow", re.I)
BARE_BOX_VERTS = 24


def bare_box(verts):
    """True for a cuboid of undetailed geometry at least a metre across."""
    if len(verts) > BARE_BOX_VERTS:
        return False
    return max(max(v[i] for v in verts) - min(v[i] for v in verts)
               for i in range(3)) * YARD > 1.0


def glb_bare_box(path):
    """bare_box() for an already-exported GLB, read from its JSON chunk.

    The export loop skips models whose GLB is already on disk, so a model
    that only later became recognisable as a placeholder would otherwise
    survive in every assets directory built before the rule existed.
    """
    with open(path, "rb") as f:
        head = f.read(20)
        j = json.loads(f.read(struct.unpack_from("<I", head, 12)[0]))
    n = span = 0
    for mesh in j["meshes"]:
        for prim in mesh["primitives"]:
            a = j["accessors"][prim["attributes"]["POSITION"]]
            n += a["count"]
            span = max(span, max(a["max"][i] - a["min"][i] for i in range(3)))
    return n <= BARE_BOX_VERTS and span > 1.0     # already in metres


def build(s, did, cfg):
    print(f"=== {did} ({cfg['map_name']}, map {cfg['ac_map']}) ===")
    wdt = find_wdt(s, cfg["map_name"])
    if not wdt:
        print("!! WDT not found, aborting")
        return False
    spawns = load_spawns(cfg["ac_map"])
    placements, obj_fdids, flags = wmo_placements(s, wdt)
    if not placements:
        print("!! no WMO placements, aborting")
        return False
    print(f"{len(placements)} WMO placements, {len(spawns)} spawns, "
          f"wdt flags {flags:#x}")
    main_uid, roots = pick_main(s, placements)
    cal = calibrate(s, spawns, placements, main_uid, roots)
    print(f"calibration: {cal['hits']}/{cal['total']} spawns inside "
          f"(det {cal['det']:+.2f})")
    if cal["total"] and cal["hits"] < cal["total"] * 0.5:
        print("!! low calibration hit rate — placements may be misaligned")
    t = Transform(cal)
    out_dir = OUT / did
    out_dir.mkdir(parents=True, exist_ok=True)

    # ---- WMO GLBs (unique fdids) ----
    wmo_names = {}
    for uid, p in sorted(placements.items()):
        fdid = p["fdid"]
        if fdid in wmo_names:
            continue
        name = f"w{fdid}"
        wmo_names[fdid] = name
        if (out_dir / f"{name}.glb").exists():
            print(f"{name}: cached")
            continue
        try:
            extract_wmo(s, fdid, name, out_dir, 1.0)
        except (CascError, KeyError, ValueError, struct.error) as e:
            print(f"{name}: FAILED {e}")
            wmo_names.pop(fdid)

    # ---- placements.json ----
    out = {"wmos": [], "creatures": [], "doodads": [], "props": []}
    needed = set()
    for uid, p in sorted(placements.items()):
        if p["fdid"] not in wmo_names:
            continue
        if all(abs(v) < 0.01 for v in p["pos"]) \
                and all(abs(v) < 0.01 for v in p["rot"]):
            w = (0.0, 0.0, 0.0)     # global-WMO map: authored at world origin
        else:
            w = world_from_file(*p["pos"])
        out["wmos"].append({
            "uid": uid, "fdid": p["fdid"],
            "glb": f"{wmo_names[p['fdid']]}.glb",
            "pos": t.to_gl(*w), "yaw": t.yaw_of(p["rot"][1]),
        })
        # this WMO's doodad set, parented to the node
        r = roots.get(p["fdid"])
        if r is None or not r.doodad_defs:
            continue
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

    # tile props (MDDF) on ADT maps
    for ofd in obj_fdids:
        oc = chunks_of(s.read_fdid(ofd))
        mddf = oc.get(b"MDDF", b"")
        mmid = oc.get(b"MMID", b"")
        mmdx = oc.get(b"MMDX", b"")
        for k in range(len(mddf) // 36):
            o = k * 36
            nid, _uid2 = struct.unpack_from("<II", mddf, o)
            px, py, pz = struct.unpack_from("<3f", mddf, o + 8)
            _rx, ryd, _rz = struct.unpack_from("<3f", mddf, o + 20)
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
                "fdid": fdid, "pos": t.to_gl(*w),
                "yaw": t.yaw_of(ryd), "scale": sc / 1024.0,
            })

    # ---- gameobjects: doors, levers, cannon, chests, veins ----
    out["gameobjects"] = []
    import re as _re
    tpl = {}
    tpl_pat = _re.compile(r"^\((\d+), ?(\d+), ?(\d+), ?'((?:[^'\\]|\\.)*)'")
    from config import AC as _AC
    for line in (_AC / "gameobject_template.sql").read_text(
            encoding="utf-8").splitlines():
        m = tpl_pat.match(line)
        if m:
            tpl[int(m.group(1))] = (int(m.group(2)), int(m.group(3)),
                                    m.group(4).replace("\\'", "'"))
    go_spawns = []
    sp_pat = _re.compile(r"^\((\d+), ?(\d+), ?%d, ?" % cfg["ac_map"])
    for line in (_AC / "gameobject.sql").read_text(
            encoding="utf-8").splitlines():
        if sp_pat.match(line):
            f = line.strip("(),;").split(",")
            go_spawns.append((int(f[1]), float(f[7]), float(f[8]),
                              float(f[9]), float(f[10])))
    if go_spawns:
        from db2 import WDC5
        gdi = WDC5(s.read_path("dbfilesclient/gameobjectdisplayinfo.db2"))
        go_dir = out_dir / "gobj"
        go_dir.mkdir(parents=True, exist_ok=True)
        exported = {}
        for entry, gx, gy, gz, go_o in go_spawns:
            ginfo = tpl.get(entry)
            if ginfo is None:
                continue
            gtype, disp, gname = ginfo
            row = gdi.rows.get(disp)
            if not row:
                continue
            fdid = row[2]     # gameobjectdisplayinfo: FileDataID after GeoBox
            if not isinstance(fdid, int) or fdid <= 0:
                continue
            if fdid not in exported:
                dest = go_dir / f"{fdid}.glb"
                okf = dest.exists()
                if not okf:
                    try:
                        gm = M2Model(s.read_fdid(fdid))
                        if gm.sfid and gm.vertices:
                            gskin = Skin(s.read_fdid(gm.sfid[0]))
                            gt = {}
                            for ti, tex in enumerate(gm.textures):
                                tf = None
                                if tex["type"] == 0:
                                    if ti < len(gm.txid) and gm.txid[ti]:
                                        tf = gm.txid[ti]
                                    elif tex["name"]:
                                        tf = s.root.fdid_for_path(tex["name"])
                                if tf:
                                    try:
                                        gt[ti] = blp_to_png(s.read_fdid(tf))
                                    except CascError:
                                        pass
                            export_static_glb(gm, gskin, gt, dest)
                            okf = True
                    except (CascError, KeyError, ValueError, struct.error) as e:
                        print(f"  gameobject {gname} model {fdid}: {e}")
                exported[fdid] = okf
            if not exported[fdid]:
                continue
            out["gameobjects"].append({
                "entry": entry, "name": gname, "type": gtype, "fdid": fdid,
                "pos": t.to_gl(gx, gy, gz),
                "yaw": t.dir_to_gl_yaw(math.cos(go_o), math.sin(go_o)),
            })
        print(f"gameobjects: {len(out['gameobjects'])} placed, "
              f"{sum(1 for v in exported.values() if v)} models")
    out["door_rules"] = cfg.get("doors", {})

    # entrance
    ent = entrance(cfg["ac_map"])
    if ent:
        ex, ey, ez, eo = ent
        out["spawn"] = {"pos": t.to_gl(ex, ey, ez),
                        "yaw": t.dir_to_gl_yaw(math.cos(eo), math.sin(eo))}
        print(f"entrance from areatrigger: world ({ex:.0f},{ey:.0f},{ez:.0f})")
    elif spawns:
        sp = spawns[0]
        out["spawn"] = {"pos": t.to_gl(sp["x"], sp["y"], sp["z"]),
                        "yaw": 0.0}
        print("!! no areatrigger entrance; spawning at first creature")

    for sp in spawns:
        out["creatures"].append({
            "guid": sp["guid"], "entry": sp["entry"],
            "pos": t.to_gl(sp["x"], sp["y"], sp["z"]),
            "yaw": t.dir_to_gl_yaw(math.cos(sp["o"]), math.sin(sp["o"])),
        })

    # ---- doodad/prop models ----
    dd_dir = out_dir / "doodads"
    dd_dir.mkdir(parents=True, exist_ok=True)
    names_path = dd_dir / "names.json"
    solid_path = dd_dir / "solid.json"
    model_names = {}
    if names_path.exists():
        model_names = json.loads(names_path.read_text())
    # fdid -> does this model block movement (see M2Model.collision_verts)
    model_solid = {}
    if solid_path.exists():
        model_solid = json.loads(solid_path.read_text())
    ok = fail = clutter = 0
    for fdid in sorted(needed):
        dest_glb = dd_dir / f"{fdid}.glb"
        if dest_glb.exists():
            ok += 1
            if str(fdid) not in model_names or str(fdid) not in model_solid:
                try:
                    m = M2Model(s.read_fdid(fdid))
                    model_names[str(fdid)] = m.name
                    model_solid[str(fdid)] = m.collision_verts > 0
                except Exception:
                    model_names.setdefault(str(fdid), "")
                    model_solid[str(fdid)] = False
            continue
        try:
            m = M2Model(s.read_fdid(fdid))
            model_names[str(fdid)] = m.name
            model_solid[str(fdid)] = m.collision_verts > 0
            if not m.sfid or not m.vertices:
                fail += 1
                continue
            name = m.name or ""
            if EFFECT_ALWAYS.search(name) or (
                    EFFECT_BOXY.search(name)
                    and bare_box([v[0:3] for v in m.vertices])):
                fail += 1
                continue
            if CLUTTER.search(m.name or ""):
                clutter += 1
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
        except (CascError, KeyError, ValueError, struct.error) as e:
            print(f"  doodad {fdid}: {e}")
            fail += 1
    print(f"doodad models: {ok} ok, {fail} failed, {clutter} clutter skipped")
    names_path.write_text(json.dumps(model_names, indent=0))
    solid_path.write_text(json.dumps(model_solid, indent=0))

    # sweep out placeholder boxes exported before the rule above existed
    effects = set()
    for fdid, name in model_names.items():
        glb = dd_dir / f"{fdid}.glb"
        if not glb.exists() or not EFFECT_BOXY.search(name or ""):
            continue
        if glb_bare_box(glb):
            effects.add(fdid)
            glb.unlink()
            print(f"  dropped particle placeholder: {name} ({fdid})")

    before = len(out["doodads"]) + len(out["props"])
    for key in ("doodads", "props"):
        out[key] = [d for d in out[key]
                    if str(d["fdid"]) not in effects
                    and not CLUTTER.search(model_names.get(str(d["fdid"]), "") or "")]
    print(f"clutter props dropped: "
          f"{before - len(out['doodads']) - len(out['props'])}")

    # Trees clipping through walls: a chunk of it is the same model stamped
    # twice at one spot. Overlapping ADT tiles and WMO doodad sets re-emit the
    # identical placement, so a tree renders doubled — two trunks in the same
    # centimetre, z-fighting, reading as a mess against a wall. Drop exact
    # (fdid, position, yaw) repeats; anything at a genuinely distinct spot
    # stays. This is safe where a blanket interior cull is not: SFK plants
    # coffins and furniture as tile-props inside its rooms, so culling props
    # by "inside a room" would delete real set dressing.
    for key in ("props", "doodads"):
        seen = set()
        kept = []
        for d in out[key]:
            sig = (d["fdid"],
                   round(d["pos"][0], 2), round(d["pos"][1], 2),
                   round(d["pos"][2], 2), round(float(d.get("yaw", 0.0)), 2))
            if sig in seen:
                continue
            seen.add(sig)
            kept.append(d)
        if len(kept) != len(out[key]):
            print(f"deduped {key}: {len(out[key]) - len(kept)} exact repeats")
        out[key] = kept

    # dungeon-level runtime hints (consumed by world.gd / player.gd)
    out["footstep"] = cfg.get("footstep", "stone")
    out["loot_generic"] = list(cfg.get("loot_generic", []))

    # Which props block movement. Sizing a collider off the render mesh made
    # the giant ferns solid, and their trimesh is a thicket of leaf blades a
    # player wedges inside; the model's own collision mesh is the real answer.
    placed_fdids = {str(d["fdid"]) for key in ("doodads", "props")
                    for d in out[key]}
    out["solid"] = sorted(int(f) for f in placed_fdids
                          if model_solid.get(f, False))
    print(f"solid props: {len(out['solid'])} of {len(placed_fdids)} models")

    with open(out_dir / "placements.json", "w") as f:
        json.dump(out, f, indent=1)
    print(f"placements: {len(out['wmos'])} wmos, {len(out['doodads'])} "
          f"doodads, {len(out['props'])} props, "
          f"{len(out['creatures'])} creatures")

    # ---- creatures ----
    build_creatures.build(s, did, cfg)

    # ---- terrain (ADT maps only) ----
    build_terrain.build_for(s, wdt, t.to_gl, out_dir / "terrain")

    # ---- ambience ----
    audio_dir = OUT / "audio"
    audio_dir.mkdir(parents=True, exist_ok=True)
    amb_file = ""
    for cand in cfg.get("ambience", []):
        for suf in ["", "day", "night"]:
            p = f"sound/ambience/zoneambience/{cand}{suf}.ogg"
            fd = s.root.fdid_for_path(p)
            if not fd:
                continue
            name = p.rsplit("/", 1)[-1]
            try:
                (audio_dir / name).write_bytes(s.read_path(p))
                amb_file = name
                print(f"ambience: {name}")
                break
            except (CascError, KeyError):
                continue
        if amb_file:
            break
    manifest_path = audio_dir / "audio.json"
    if manifest_path.exists():
        man = json.loads(manifest_path.read_text())
        byd = man.get("dungeon_ambience", {})
        if amb_file:
            byd[did] = amb_file
        man["dungeon_ambience"] = byd
        manifest_path.write_text(json.dumps(man, indent=1))
    if not amb_file:
        print("ambience: none matched (default cave loop plays)")
    return True


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dungeon", action="append", default=[])
    ap.add_argument("--all", action="store_true")
    args = ap.parse_args()
    targets = list(DUNGEONS) if args.all else (args.dungeon or [])
    if not targets:
        ap.error("pass --dungeon <id> (repeatable) or --all")
    # check every id before opening CASC: a typo in the third --dungeon used
    # to surface as a bare KeyError after the first two had already built
    unknown = [d for d in targets if d not in DUNGEONS]
    if unknown:
        ap.error("unknown dungeon %s. Configured: %s"
                 % (", ".join(repr(d) for d in unknown), ", ".join(sorted(DUNGEONS))))
    s = Storage()
    done = []
    for did in targets:
        if build(s, did, DUNGEONS[did]):
            done.append(did)
    print(f"\nbuilt: {', '.join(done)}")


if __name__ == "__main__":
    main()
