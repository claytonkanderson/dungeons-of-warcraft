"""Extract a dungeon's WMOs (extract_wmo is the generic exporter every
dungeon uses; the WMOS list and main() below are Deadmines-only).

Originally: extract the Deadmines instance WMOs to assets/out/deadmines/.

Milestone 1: main dungeon WMO (108483) + exit WMO (108538) as GLBs.
"""
import argparse
from pathlib import Path

from config import OUT
from casc import Storage, CascError
from wmo import WMORoot, WMOGroup
from wmo_export import export_wmo_glb, LIQUID_TEXTURES
from blp import blp_to_png

WMOS = {
    "deadmines": 108483,   # 'The Deadmines' — the dungeon itself
    "exit": 108538,        # exit tunnel
    "wall_tower": 113966,  # map-edge wall pieces
    "wall_solid": 113970,
    "boat_es01": 114107,   # rowboats at the cove dock
    "boat_sc2": 114109,
}


def extract_wmo(s, fdid, name, out_dir, vc_scale):
    root = WMORoot(s.read_fdid(fdid))
    groups = []
    for gi, gfdid in enumerate(root.group_fdids):
        if not gfdid:
            continue
        try:
            groups.append((gi, WMOGroup(s.read_fdid(gfdid))))
        except CascError as e:
            print(f"  group {gi} unavailable: {e}")
    textures = {}
    from build_creatures import nearest_blp
    for m in root.materials:
        for key in ("texture1",):
            fdid_t = m[key]
            if fdid_t and fdid_t not in textures:
                try:
                    textures[fdid_t] = blp_to_png(s.read_fdid(fdid_t))
                except CascError as e:
                    # not in the local client (the Anniversary client streams
                    # on demand): a tile set is numbered together, so the
                    # neighbouring file is the same family of stone or wood,
                    # and beats leaving the faces untextured white
                    alt = nearest_blp(s, fdid_t)
                    if alt:
                        textures[fdid_t] = blp_to_png(s.read_fdid(alt))
                        print(f"!! texture {fdid_t} not local; using neighbour {alt}")
                    else:
                        print(f"!! texture {fdid_t}: {e} (faces left bare)")
    # the liquid surfaces' tiling textures, keyed by file id like the rest
    for tf in LIQUID_TEXTURES.values():
        if tf not in textures:
            try:
                textures[tf] = blp_to_png(s.read_fdid(tf))
            except Exception:
                pass
    info = export_wmo_glb(root, groups, textures,
                          out_dir / f"{name}.glb",
                          out_dir / f"{name}_meta.json",
                          vc_scale=vc_scale)
    print(f"{name}: {info['groups']} groups, {info['vertices']} verts, "
          f"{len(textures)} textures, {info['size']/1e6:.1f} MB")
    return root


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--vc-scale", type=float, default=1.0,
                    help="multiplier for baked vertex colors")
    args = ap.parse_args()
    out_dir = OUT / "deadmines"
    out_dir.mkdir(parents=True, exist_ok=True)
    s = Storage()
    for name, fdid in WMOS.items():
        extract_wmo(s, fdid, name, out_dir, args.vc_scale)


if __name__ == "__main__":
    main()
