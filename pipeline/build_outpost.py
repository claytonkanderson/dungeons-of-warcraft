"""The Outpost's two models, from the WoW client: the goblin who gambles
and buys (a creature display, exported like a dungeon's creatures with its
idle animation) and the chest that is the stash (a gameobject display,
exported static). One folder for every dungeon:

  assets/wow/outpost/vendor.glb, stash.glb, outpost.json

The vendor is a goblin because goblins are Warcraft's traders; the
display is the Goblin Engineer's (the Deadmines' pipeline already proved
that model reads). Each has a short list of fallbacks in case a client
never streamed the first.

  python pipeline/build_outpost.py
"""
import json
import struct

from config import OUT
from casc import Storage, CascError
from db2 import WDC5
from m2 import M2Model, Skin
from blp import blp_to_png
import gltf_export
from build_creatures import GAME_SEQS, HAIR_FALLBACK_RGBA, RACE_FOLDER, f32, nearest_blp

# creaturedisplayinfo ids, in order of preference: Goblin Engineer,
# Goblin Woodcarver, Goblin Craftsman (all GoblinMale)
VENDOR_DISPLAYS = [7109, 7111, 7110]
# gameobjectdisplayinfo ids: Large Mithril Bound Chest and Large Solid
# Chest share 259; then the plain chests of the low dungeons
STASH_DISPLAYS = [259, 10, 41, 1, 1387]


def _readable(s, fd):
    if not fd:
        return False
    try:
        return s.read_fdid(fd)[:4] == b"BLP2"
    except (CascError, KeyError):
        return False


def export_vendor(s, out_dir):
    cdi = WDC5(s.read_path("dbfilesclient/creaturedisplayinfo.db2"))
    cmd = WDC5(s.read_path("dbfilesclient/creaturemodeldata.db2"))
    cde = WDC5(s.read_path("dbfilesclient/creaturedisplayinfoextra.db2"))
    hairgeo = WDC5(s.read_path("dbfilesclient/charhairgeosets.db2"))
    # model fdid -> every display's texture variation set that uses it
    model_variations = {}
    for _d, r in cdi.rows.items():
        fd = cmd.rows.get(r[1], (None, None, None))[2]
        if fd and isinstance(r[25], list) and any(r[25]):
            model_variations.setdefault(fd, []).append(r[25])
    for disp in VENDOR_DISPLAYS:
        row = cdi.rows.get(disp)
        if not row:
            print(f"vendor: display {disp} unknown to this client")
            continue
        model_fdid = cmd.rows[row[1]][2]
        scale = f32(row[4]) or 1.0
        extra_id = row[7]
        variations = row[25] if isinstance(row[25], list) else []

        def anim_resolver(seq_id, variation, afid):
            fd = afid.get((seq_id, variation))
            if fd:
                try:
                    return s.read_fdid(fd)
                except CascError:
                    return None
            return None

        try:
            model = M2Model(s.read_fdid(model_fdid), anim_resolver, s.read_fdid)
            skin = Skin(s.read_fdid(model.sfid[0]))
        except (CascError, KeyError, ValueError, struct.error) as e:
            print(f"vendor: display {disp} model {model_fdid} failed: {e}")
            continue
        textures, flat, geosets = {}, {}, None
        if extra_id and extra_id in cde.rows:
            # a character-style NPC (the goblins are): the baked NPC skin, or
            # the race's base skin when the bake never streamed; the hair
            # geoset the extra row names, plus the bare body geosets
            erow = cde.rows[extra_id]
            race, sex, style = erow[1], erow[2], erow[5]
            baked = s.root.fdid_for_path(
                f"textures/bakednpctextures/creaturedisplayextra-{extra_id:05d}.blp")
            hair_geoset = 0
            for _rid, hrow in hairgeo.rows.items():
                if hrow[0] == race and hrow[1] == sex and hrow[2] == style:
                    hair_geoset = hrow[3]
                    break
            geosets = {0, hair_geoset, 101, 201, 301, 401, 501, 702, 1301}
            folder = RACE_FOLDER.get(race, "")
            sexdir = "female" if sex == 1 else "male"
            hair_tex = s.root.fdid_for_path(f"character/{folder}/hair00_00.blp") \
                if folder else None
            skin_fallback = s.root.fdid_for_path(
                f"character/{folder}/{sexdir}/{folder}{sexdir}skin00_00.blp") \
                if folder else None
            for i, tex in enumerate(model.textures):
                if tex["type"] == 1:
                    for cand in (baked, skin_fallback):
                        if cand and _readable(s, cand):
                            textures[i] = blp_to_png(s.read_fdid(cand))
                            break
                elif tex["type"] == 6 and hair_tex and _readable(s, hair_tex):
                    textures[i] = blp_to_png(s.read_fdid(hair_tex))
                elif tex["type"] == 0 and i < len(model.txid) and model.txid[i]:
                    textures[i] = blp_to_png(s.read_fdid(model.txid[i]))
            for i in range(len(model.textures)):
                if i not in textures:
                    flat[i] = HAIR_FALLBACK_RGBA
        else:
            for i, tex in enumerate(model.textures):
                cands = []
                if tex["type"] == 0 and i < len(model.txid) and model.txid[i]:
                    cands = [model.txid[i]]
                elif tex["type"] in (11, 12, 13):
                    k = tex["type"] - 11
                    cands = [variations[k] if k < len(variations) else 0]
                    cands += [v[k] for v in model_variations.get(model_fdid, []) if k < len(v)]
                cands = [c for c in cands if c]
                fd = next((c for c in cands if _readable(s, c)), None)
                if fd is None and cands:
                    fd = nearest_blp(s, cands[0])
                if fd:
                    textures[i] = blp_to_png(s.read_fdid(fd))
                elif cands or tex["type"] in (1, 2, 6, 11, 12, 13):
                    flat[i] = HAIR_FALLBACK_RGBA
        if not textures:
            print(f"vendor: display {disp} has no readable texture; next")
            continue
        dest = out_dir / "vendor.glb"
        try:
            info = gltf_export.export_glb(model, skin, textures, dest,
                                          seq_filter=GAME_SEQS, allowed_geosets=geosets,
                                          flat_colors=flat)
            if not info["animations"]:
                info = gltf_export.export_glb(model, skin, textures, dest,
                                              seq_filter=None, allowed_geosets=geosets,
                                              flat_colors=flat)
        except (CascError, KeyError, ValueError, struct.error) as e:
            print(f"vendor: display {disp} export failed: {e}")
            continue
        print(f"vendor: {model.name} (display {disp}) scale={scale:.2f} "
              f"{len(textures)} tex, {info['size'] // 1024} KB, "
              f"{len(info['animations'])} anims")
        return {"display": disp, "model": model.name, "scale": scale,
                "anims": info["animations"]}
    print("!! vendor: no display could be exported; the game draws a stand-in")
    return None


def export_stash(s, out_dir):
    from build_dungeon import _texture_or_neighbour
    gdi = WDC5(s.read_path("dbfilesclient/gameobjectdisplayinfo.db2"))
    for disp in STASH_DISPLAYS:
        row = gdi.rows.get(disp)
        if not row:
            continue
        fdid = row[2]
        if not isinstance(fdid, int) or fdid <= 0:
            continue
        try:
            gm = M2Model(s.read_fdid(fdid))
            if not (gm.sfid and gm.vertices):
                continue
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
                    png = _texture_or_neighbour(s, tf, "the stash chest")
                    if png:
                        gt[ti] = png
            dest = out_dir / "stash.glb"
            info = gltf_export.export_static_glb(gm, gskin, gt, dest)
        except (CascError, KeyError, ValueError, struct.error) as e:
            print(f"stash: display {disp} model {fdid}: {e}")
            continue
        print(f"stash: {gm.name} (display {disp}, model {fdid}) {info['size'] // 1024} KB")
        return {"display": disp, "fdid": fdid, "model": gm.name}
    print("!! stash: no chest display could be exported; the game draws a stand-in")
    return None


def build(s):
    out_dir = OUT / "outpost"
    out_dir.mkdir(parents=True, exist_ok=True)
    info = {"vendor": export_vendor(s, out_dir), "stash": export_stash(s, out_dir)}
    with open(out_dir / "outpost.json", "w") as f:
        json.dump(info, f, indent=1)
    print(f"outpost -> {out_dir}")


if __name__ == "__main__":
    build(Storage())
