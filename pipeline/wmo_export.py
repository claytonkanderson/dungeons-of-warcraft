"""WMO -> GLB: one node+mesh per group, primitive per render batch.

Materials are exported unlit (KHR_materials_unlit) with the group's
baked vertex colors in COLOR_0 — that's where WMO interiors get their
lighting, so the result matches the in-game look without any Godot
lights. Groups lacking MOCV get white.
"""
import json
import struct

from gltf_export import _cv, YARD


def export_wmo_glb(root, groups, textures, out_path, meta_path=None,
                   vc_scale=1.0):
    """groups: [(index, WMOGroup)]; textures: {fdid: png_bytes}"""
    buf = bytearray()
    views, accessors = [], []

    def view(blob, target=None, align=4):
        while len(buf) % align:
            buf.append(0)
        ofs = len(buf)
        buf.extend(blob)
        v = {"buffer": 0, "byteOffset": ofs, "byteLength": len(blob)}
        if target:
            v["target"] = target
        views.append(v)
        return len(views) - 1

    def acc(vi, ctype, count, atype, **kw):
        accessors.append({"bufferView": vi, "componentType": ctype,
                          "count": count, "type": atype, **kw})
        return len(accessors) - 1

    # ----- materials (shared across groups)
    images, gl_textures, materials_out = [], [], []
    tex_index = {}
    for mi, m in enumerate(root.materials):
        mat = {"pbrMetallicRoughness": {"metallicFactor": 0.0,
                                        "roughnessFactor": 1.0},
               "name": f"wmo_mat{mi}",
               "extensions": {"KHR_materials_unlit": {}}}
        fdid = m["texture1"]
        if fdid in textures:
            if fdid not in tex_index:
                images.append({"bufferView": view(textures[fdid]),
                               "mimeType": "image/png"})
                gl_textures.append({"source": len(images) - 1, "sampler": 0})
                tex_index[fdid] = len(gl_textures) - 1
            mat["pbrMetallicRoughness"]["baseColorTexture"] = \
                {"index": tex_index[fdid]}
        if m["blend"] == 1:
            mat["alphaMode"] = "MASK"
            mat["alphaCutoff"] = 0.5
        elif m["blend"] >= 2:
            mat["alphaMode"] = "BLEND"
        if m["flags"] & 0x04:
            mat["doubleSided"] = True
        materials_out.append(mat)
    liquid_mat = len(materials_out)
    materials_out.append({
        "pbrMetallicRoughness": {"metallicFactor": 0.0,
                                 "roughnessFactor": 1.0,
                                 "baseColorFactor": [0.08, 0.26, 0.34, 0.55]},
        "alphaMode": "BLEND", "doubleSided": True, "name": "wmo_liquid",
        "extensions": {"KHR_materials_unlit": {}}})

    # ----- groups
    nodes, meshes, meta_groups = [], [], []
    for gi, g in groups:
        info = root.group_names[gi]
        if not g.vertices or not g.batches:
            continue
        pos = [tuple(c * YARD for c in _cv(v)) for v in g.vertices]
        nrm = [_cv(v) for v in g.normals]
        pos_blob = b"".join(struct.pack("<3f", *p) for p in pos)
        mins = [min(p[i] for p in pos) for i in range(3)]
        maxs = [max(p[i] for p in pos) for i in range(3)]
        a_pos = acc(view(pos_blob, 34962), 5126, len(pos), "VEC3",
                    min=mins, max=maxs)
        a_nrm = acc(view(b"".join(struct.pack("<3f", *v) for v in nrm),
                         34962), 5126, len(pos), "VEC3")
        a_uv = acc(view(b"".join(struct.pack("<2f", *t) for t in g.uvs),
                        34962), 5126, len(pos), "VEC2")
        col = bytearray()
        if g.colors:
            for b, gr, r, a in g.colors:
                col += bytes((min(255, int(r * vc_scale)),
                              min(255, int(gr * vc_scale)),
                              min(255, int(b * vc_scale)), 255))
        else:
            col = bytearray(b"\xff\xff\xff\xff" * len(pos))
        a_col = acc(view(bytes(col), 34962), 5121, len(pos), "VEC4",
                    normalized=True)

        prims = []
        for batch in g.batches:
            ids = g.indices[batch["start"]:batch["start"] + batch["count"]]
            a_idx = acc(view(b"".join(struct.pack("<H", i) for i in ids),
                             34963), 5123, len(ids), "SCALAR")
            prims.append({"attributes": {"POSITION": a_pos, "NORMAL": a_nrm,
                                         "TEXCOORD_0": a_uv,
                                         "COLOR_0": a_col},
                          "indices": a_idx,
                          "material": batch["material"]})
        meshes.append({"primitives": prims, "name": info["name"] or f"g{gi}"})
        nodes.append({"name": info["name"] or f"group{gi}",
                      "mesh": len(meshes) - 1})
        # liquid surface as its own node ("liquid*" — the game skips
        # collision on these)
        if g.liquid:
            L = g.liquid
            LT = 4.1666665
            cx, cy, cz = L["corner"]
            lpos = []
            for j in range(L["yv"]):
                for i in range(L["xv"]):
                    w = (cx + i * LT, cy + j * LT,
                         L["heights"][j * L["xv"] + i])
                    lpos.append(tuple(c * YARD for c in _cv(w)))
            lids = []
            for ty in range(L["yt"]):
                for tx in range(L["xt"]):
                    f = L["tiles"][ty * L["xt"] + tx]
                    if (f & 0x0F) == 0x0F:
                        continue
                    v0 = ty * L["xv"] + tx
                    v1 = v0 + 1
                    v2 = v0 + L["xv"]
                    v3 = v2 + 1
                    lids += [v0, v1, v2, v1, v3, v2]
            if lids:
                lblob = b"".join(struct.pack("<3f", *p) for p in lpos)
                lmins = [min(p[i] for p in lpos) for i in range(3)]
                lmaxs = [max(p[i] for p in lpos) for i in range(3)]
                a_lp = acc(view(lblob, 34962), 5126, len(lpos), "VEC3",
                           min=lmins, max=lmaxs)
                a_li = acc(view(b"".join(struct.pack("<H", i) for i in lids),
                                34963), 5123, len(lids), "SCALAR")
                meshes.append({"primitives": [{
                    "attributes": {"POSITION": a_lp}, "indices": a_li,
                    "material": liquid_mat}], "name": f"liquid{gi}"})
                nodes.append({"name": f"liquid{gi}",
                              "mesh": len(meshes) - 1})
        bb = info["bbox"]
        c0 = tuple(c * YARD for c in _cv(bb[0:3]))
        c1 = tuple(c * YARD for c in _cv(bb[3:6]))
        meta_groups.append({
            "index": gi, "name": info["name"], "flags": info["flags"],
            "center": [(c0[i] + c1[i]) / 2 for i in range(3)],
            "min": [min(c0[i], c1[i]) for i in range(3)],
            "max": [max(c0[i], c1[i]) for i in range(3)],
            "vertices": len(pos), "batches": len(g.batches),
            "has_vcolors": g.colors is not None,
        })

    gltf = {
        "asset": {"version": "2.0", "generator": "warcraft-art wmo"},
        "extensionsUsed": ["KHR_materials_unlit"],
        "scene": 0,
        "scenes": [{"nodes": list(range(len(nodes)))}],
        "nodes": nodes,
        "meshes": meshes,
        "materials": materials_out,
        "accessors": accessors,
        "bufferViews": views,
        "buffers": [{"byteLength": len(buf)}],
        "samplers": [{"wrapS": 10497, "wrapT": 10497,
                      "magFilter": 9729, "minFilter": 9987}],
    }
    if images:
        gltf["images"] = images
        gltf["textures"] = gl_textures

    js = json.dumps(gltf, separators=(",", ":")).encode()
    js += b" " * ((4 - len(js) % 4) % 4)
    bin_data = bytes(buf) + b"\0" * ((4 - len(buf) % 4) % 4)
    glb = (struct.pack("<III", 0x46546C67, 2, 28 + len(js) + len(bin_data))
           + struct.pack("<II", len(js), 0x4E4F534A) + js
           + struct.pack("<II", len(bin_data), 0x004E4942) + bin_data)
    with open(out_path, "wb") as f:
        f.write(glb)
    if meta_path:
        with open(meta_path, "w") as f:
            json.dump({"groups": meta_groups}, f, indent=1)
    return {"groups": len(meshes), "size": len(glb),
            "vertices": sum(m["vertices"] for m in meta_groups)}
