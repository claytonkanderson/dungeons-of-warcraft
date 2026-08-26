"""Extract one creature M2 from CASC and emit a GLB + PNGs.

Usage:
  python extract_creature.py creature/murloc/murloc.m2 --skin 125025
--skin: fdid of the BLP for type>0 (replaceable, e.g. monster skin) slots.
"""
import argparse
import posixpath
import sys
from pathlib import Path

from config import RAW, OUT
from casc import Storage, CascError
from m2 import M2Model, Skin
from blp import blp_to_png
import gltf_export


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("path")
    ap.add_argument("--skin", type=int, default=None,
                    help="fdid of BLP for replaceable texture slots")
    ap.add_argument("--tex", action="append", default=[],
                    help="TYPE=FDID override for a replaceable slot, "
                         "e.g. --tex 1=569980 --tex 6=119905")
    ap.add_argument("--geosets", default=None,
                    help="comma-separated submesh ids to keep (default all)")
    ap.add_argument("--weapon", action="append", default=[],
                    help="ATTACHID=MODELFDID,TEXFDID rigid attachment "
                         "(1=right hand, 2=left hand), e.g. "
                         "--weapon 1=148115,148117")
    ap.add_argument("--out", default=None)
    args = ap.parse_args()
    tex_by_type = {}
    for spec in args.tex:
        k, _, v = spec.partition("=")
        tex_by_type[int(k)] = int(v)

    s = Storage()
    m2_bytes = s.read_path(args.path)
    stem = posixpath.basename(args.path).rsplit(".", 1)[0]
    folder = posixpath.dirname(args.path)
    RAW.mkdir(parents=True, exist_ok=True)
    OUT.mkdir(parents=True, exist_ok=True)
    (RAW / f"{stem}.m2").write_bytes(m2_bytes)

    def anim_resolver(seq_id, variation, afid):
        fdid = afid.get((seq_id, variation))
        try:
            if fdid:
                return s.read_fdid(fdid)
            return s.read_path(f"{folder}/{stem}{seq_id:04d}-{variation:02d}.anim")
        except CascError as e:
            print(f"  [anim {seq_id}-{variation}] unavailable: {e}")
            return None

    model = M2Model(m2_bytes, anim_resolver, s.read_fdid)
    ext = sum(0 if model.seq_inline(i) else 1 for i in range(len(model.sequences)))
    print(f"model {model.name}: {len(model.bones)} bones, "
          f"{len(model.sequences)} sequences ({ext} external), "
          f"{len(model.vertices)} verts, textures={model.textures}")

    if not model.sfid:
        raise SystemExit("no SFID chunk; skin fdid unknown")
    skin_bytes = s.read_fdid(model.sfid[0])
    (RAW / f"{stem}00.skin").write_bytes(skin_bytes)
    skin = Skin(skin_bytes)
    print(f"skin: {len(skin.submeshes)} submeshes, {len(skin.batches)} batches")

    textures = {}
    for i, tex in enumerate(model.textures):
        fdid = None
        if tex["type"] == 0:
            if i < len(model.txid) and model.txid[i]:
                fdid = model.txid[i]
            elif tex["name"]:
                fdid = s.root.fdid_for_path(tex["name"])
        else:
            fdid = tex_by_type.get(tex["type"], args.skin)
        if not fdid:
            print(f"  texture[{i}] type={tex['type']}: unresolved, skipping")
            continue
        try:
            png = blp_to_png(s.read_fdid(fdid))
        except CascError as e:
            print(f"  texture[{i}] fdid {fdid}: {e}")
            continue
        textures[i] = png
        (OUT / f"{stem}_tex{i}_{fdid}.png").write_bytes(png)
        print(f"  texture[{i}] type={tex['type']} fdid={fdid} -> png")

    attachments = []
    for spec in args.weapon:
        aid, _, rest = spec.partition("=")
        model_fdid, _, tex_fdid = rest.partition(",")
        wm = M2Model(s.read_fdid(int(model_fdid)))
        wskin = Skin(s.read_fdid(wm.sfid[0]))
        wtex = {}
        for i, tex in enumerate(wm.textures):
            fdid = None
            if tex["type"] == 0 and i < len(wm.txid) and wm.txid[i]:
                fdid = wm.txid[i]
            elif tex["type"] != 0 and tex_fdid:
                fdid = int(tex_fdid)
            if fdid:
                wtex[i] = blp_to_png(s.read_fdid(fdid))
        attachments.append({"attach_id": int(aid), "model": wm,
                            "skin": wskin, "textures": wtex})
        print(f"  weapon attach {aid}: {wm.name} "
              f"({len(wm.vertices)} verts, {len(wtex)} textures)")

    allowed = None
    if args.geosets:
        allowed = {int(x) for x in args.geosets.split(",")}
    out_path = Path(args.out) if args.out else OUT / f"{stem}.glb"
    info = gltf_export.export_glb(model, skin, textures, out_path,
                                  allowed_geosets=allowed,
                                  attachments=attachments)
    print(f"wrote {out_path} ({info['size']} bytes): "
          f"{info['primitives']} prims, {info['bones']} bones, "
          f"{len(info['animations'])} animations")
    print("animations:", ", ".join(info["animations"]))


if __name__ == "__main__":
    main()
