"""Build a skinned, animated GLB from a parsed M2 + skin + textures.

Basis change WoW -> glTF: wow (X fwd, Y left, Z up) to gl (Y up, -Z fwd):
  v' = (-v.y, v.z, -v.x)      quaternions map the same way on (x,y,z)
Applied uniformly to every local transform, so hierarchies stay intact.
"""
import json
import math
import struct

YARD = 0.9144  # wow unit (yard) -> meters

ANIM_NAMES = {
    0: "Stand", 1: "Death", 2: "Spell", 3: "Stop", 4: "Walk", 5: "Run",
    6: "Dead", 7: "Rise", 8: "StandWound", 9: "CombatWound", 10: "CombatCritical",
    11: "ShuffleLeft", 12: "ShuffleRight", 13: "Walkbackwards", 14: "Stun",
    15: "HandsClosed", 16: "AttackUnarmed", 17: "Attack1H", 18: "Attack2H",
    19: "Attack2HL", 20: "ParryUnarmed", 21: "Parry1H", 22: "Parry2H",
    23: "Parry2HL", 24: "ShieldBlock", 25: "ReadyUnarmed", 26: "Ready1H",
    27: "Ready2H", 28: "Ready2HL", 29: "ReadyBow", 30: "Dodge",
    31: "SpellPrecast", 32: "SpellCast", 33: "SpellCastArea", 34: "NPCWelcome",
    35: "NPCGoodbye", 36: "Block", 37: "JumpStart", 38: "Jump", 39: "JumpEnd",
    40: "Fall", 41: "SwimIdle", 42: "Swim", 43: "SwimLeft", 44: "SwimRight",
    45: "SwimBackwards", 46: "AttackBow", 47: "FireBow", 48: "ReadyRifle",
    49: "AttackRifle", 50: "Loot", 51: "ReadySpellDirected", 60: "Kick",
    64: "Talk", 65: "EmoteEat", 66: "EmoteWork", 67: "EmoteUseStanding",
    69: "EmoteDance", 70: "EmoteLaugh", 91: "EmoteRoar",
}


def _png_lum_alpha(png):
    """Rewrite a write_png-produced RGBA PNG so alpha = max(R,G,B).
    Additive-blend art encodes transparency as black; under glTF alpha
    blending that black renders as solid sheets (the RFC fire silhouettes,
    the frozen waterfall cones). Luminance-as-alpha approximates additive."""
    import zlib
    from blp import write_png
    w, h = struct.unpack(">II", png[16:24])
    p = 8
    idat = b""
    while p < len(png):
        ln = struct.unpack(">I", png[p:p + 4])[0]
        if png[p + 4:p + 8] == b"IDAT":
            idat += png[p + 8:p + 8 + ln]
        p += 12 + ln
    raw = bytearray(zlib.decompress(idat))
    stride = w * 4 + 1
    for y in range(h):
        base = y * stride + 1
        for x in range(w):
            o = base + x * 4
            raw[o + 3] = max(raw[o], raw[o + 1], raw[o + 2])
    rgba = b"".join(bytes(raw[y * stride + 1:(y + 1) * stride])
                    for y in range(h))
    return write_png(w, h, rgba)


def _cv(v):  # convert vector
    return (-v[1], v[2], -v[0])


def _cq(q):  # convert quaternion (x,y,z,w)
    return (-q[1], q[2], -q[0], q[3])


def _decomp_quat(raw):
    x, y, z, w = [((v & 0xFFFF) - 32767) / 32767.0 for v in raw]
    n = math.sqrt(x * x + y * y + z * z + w * w) or 1.0
    return (x / n, y / n, z / n, w / n)


class _Buf:
    def __init__(self):
        self.data = bytearray()

    def add(self, blob, align=4):
        while len(self.data) % align:
            self.data.append(0)
        ofs = len(self.data)
        self.data += blob
        return ofs


def export_static_glb(model, skin, textures, out_path):
    """Rigid (unskinned, unanimated) M2 -> GLB. For WMO doodads and props.
    Unlit materials to match the pre-baked WMO look."""
    buf = _Buf()
    views, accessors = [], []

    def view(blob, target=None, align=4):
        ofs = buf.add(blob, align)
        v = {"buffer": 0, "byteOffset": ofs, "byteLength": len(blob)}
        if target:
            v["target"] = target
        views.append(v)
        return len(views) - 1

    def acc(vi, ctype, count, atype, **kw):
        accessors.append({"bufferView": vi, "componentType": ctype,
                          "count": count, "type": atype, **kw})
        return len(accessors) - 1

    n_vert = len(model.vertices)
    pos = [tuple(c * YARD for c in _cv(v[0:3])) for v in model.vertices]
    a_pos = acc(view(b"".join(struct.pack("<3f", *p) for p in pos), 34962),
                5126, n_vert, "VEC3",
                min=[min(p[i] for p in pos) for i in range(3)],
                max=[max(p[i] for p in pos) for i in range(3)])
    a_nrm = acc(view(b"".join(struct.pack("<3f", *_cv(v[11:14]))
                              for v in model.vertices), 34962),
                5126, n_vert, "VEC3")
    a_uv = acc(view(b"".join(struct.pack("<2f", *v[14:16])
                             for v in model.vertices), 34962),
               5126, n_vert, "VEC2")

    global_idx = [skin.vertices[i] for i in skin.indices]
    prims, mats, images, gl_texs, tex_out = [], [], [], [], {}
    for b in skin.batches:
        sm = skin.submeshes[b["section"]]
        ids = global_idx[sm["index_start"]:sm["index_start"] + sm["index_count"]]
        if not ids:
            continue
        a_idx = acc(view(b"".join(struct.pack("<H", i) for i in ids), 34963),
                    5123, len(ids), "SCALAR")
        m2tex = model.tex_lookup[b["tex_combo"]] if model.tex_lookup else 0
        mflags, blend = model.materials[b["material"]]
        mat = {"pbrMetallicRoughness": {"metallicFactor": 0.0,
                                        "roughnessFactor": 1.0},
               "extensions": {"KHR_materials_unlit": {}}}
        additive = blend >= 3
        if m2tex in textures:
            tkey = (m2tex, additive)
            if tkey not in tex_out:
                png = _png_lum_alpha(textures[m2tex]) if additive \
                    else textures[m2tex]
                images.append({"bufferView": view(png),
                               "mimeType": "image/png"})
                gl_texs.append({"source": len(images) - 1, "sampler": 0})
                tex_out[tkey] = len(gl_texs) - 1
            mat["pbrMetallicRoughness"]["baseColorTexture"] = \
                {"index": tex_out[tkey]}
        if blend == 1:
            mat["alphaMode"] = "MASK"
            mat["alphaCutoff"] = 0.5
        elif blend >= 2:
            mat["alphaMode"] = "BLEND"
        if mflags & 0x04 or additive:
            mat["doubleSided"] = True
        mats.append(mat)
        prims.append({"attributes": {"POSITION": a_pos, "NORMAL": a_nrm,
                                     "TEXCOORD_0": a_uv},
                      "indices": a_idx, "material": len(mats) - 1})

    gltf = {"asset": {"version": "2.0", "generator": "warcraft-art static"},
            "extensionsUsed": ["KHR_materials_unlit"],
            "scene": 0, "scenes": [{"nodes": [0]}],
            "nodes": [{"name": model.name or "doodad", "mesh": 0}],
            "meshes": [{"primitives": prims}],
            "materials": mats, "accessors": accessors, "bufferViews": views,
            "buffers": [{"byteLength": len(buf.data)}],
            "samplers": [{"wrapS": 10497, "wrapT": 10497,
                          "magFilter": 9729, "minFilter": 9987}]}
    if images:
        gltf["images"] = images
        gltf["textures"] = gl_texs
    js = json.dumps(gltf, separators=(",", ":")).encode()
    js += b" " * ((4 - len(js) % 4) % 4)
    bin_data = bytes(buf.data) + b"\0" * ((4 - len(buf.data) % 4) % 4)
    glb = (struct.pack("<III", 0x46546C67, 2, 28 + len(js) + len(bin_data))
           + struct.pack("<II", len(js), 0x4E4F534A) + js
           + struct.pack("<II", len(bin_data), 0x004E4942) + bin_data)
    with open(out_path, "wb") as f:
        f.write(glb)
    return {"size": len(glb), "prims": len(prims)}


def export_glb(model, skin, textures, out_path, seq_filter=None,
               allowed_geosets=None, attachments=None, flat_colors=None):
    """textures: {m2_texture_index: png_bytes};
    flat_colors: {m2_texture_index: (r, g, b, a)} for slots with no texture
    to give — the material gets a baseColorFactor instead of rendering white
    (hair geosets of races whose hair texture is not in the local client);
    allowed_geosets: set of submesh (geoset) ids to keep, None = all;
    attachments: [{'attach_id': int, 'model': M2Model, 'skin': Skin,
                   'textures': {idx: png}}] rigid meshes hung on the
    bone of the matching attachment point (1=right hand, 2=left hand)."""
    buf = _Buf()
    views, accessors = [], []

    def view(blob, target=None, align=4):
        ofs = buf.add(blob, align)
        v = {"buffer": 0, "byteOffset": ofs, "byteLength": len(blob)}
        if target:
            v["target"] = target
        views.append(v)
        return len(views) - 1

    def acc(vi, ctype, count, atype, **kw):
        a = {"bufferView": vi, "componentType": ctype, "count": count,
             "type": atype, **kw}
        accessors.append(a)
        return len(accessors) - 1

    materials_out = []
    images, gl_textures = [], []

    def build_primitives(mdl, skn, texs, skinned, geoset_filter=None):
        """Returns a glTF primitives list for one model+skin."""
        n_vert = len(mdl.vertices)
        pos, norm, uv = [], [], []
        joints, weights = bytearray(), bytearray()
        for v in mdl.vertices:
            p = _cv(v[0:3])
            pos.append(tuple(c * YARD for c in p))
            norm.append(_cv(v[11:14]))
            uv.append(v[14:16])
            joints += bytes(v[7:11])
            weights += bytes(v[3:7])
        pos_blob = b"".join(struct.pack("<3f", *p) for p in pos)
        mins = [min(p[i] for p in pos) for i in range(3)]
        maxs = [max(p[i] for p in pos) for i in range(3)]
        attrs = {
            "POSITION": acc(view(pos_blob, 34962), 5126, n_vert, "VEC3",
                            min=mins, max=maxs),
            "NORMAL": acc(view(b"".join(struct.pack("<3f", *n) for n in norm),
                               34962), 5126, n_vert, "VEC3"),
            "TEXCOORD_0": acc(view(b"".join(struct.pack("<2f", *t) for t in uv),
                                   34962), 5126, n_vert, "VEC2"),
        }
        if skinned:
            attrs["JOINTS_0"] = acc(view(bytes(joints), 34962), 5121,
                                    n_vert, "VEC4")
            attrs["WEIGHTS_0"] = acc(view(bytes(weights), 34962), 5121,
                                     n_vert, "VEC4", normalized=True)

        global_idx = [skn.vertices[i] for i in skn.indices]
        prims = []
        tex_out = {}   # m2 texture index -> gltf texture index (this model)
        seen_layer0 = set()
        for b in skn.batches:
            sm = skn.submeshes[b["section"]]
            if geoset_filter is not None and sm["id"] not in geoset_filter:
                continue
            if b["layer"] > 0 and b["section"] in seen_layer0:
                continue  # skip overlay layers; base layer already drawn
            seen_layer0.add(b["section"])
            ids = global_idx[sm["index_start"]:
                             sm["index_start"] + sm["index_count"]]
            idx_blob = b"".join(struct.pack("<H", i) for i in ids)
            a_idx = acc(view(idx_blob, 34963), 5123, len(ids), "SCALAR")

            m2tex = mdl.tex_lookup[b["tex_combo"]] if mdl.tex_lookup else 0
            mflags, blend = mdl.materials[b["material"]]
            mat = {"pbrMetallicRoughness": {"metallicFactor": 0.0,
                                            "roughnessFactor": 1.0},
                   "name": f"{mdl.name}_mat{b['material']}_tex{m2tex}"}
            additive = blend >= 3
            if m2tex in texs:
                tkey = (m2tex, additive)
                if tkey not in tex_out:
                    png = _png_lum_alpha(texs[m2tex]) if additive \
                        else texs[m2tex]
                    images.append({"bufferView": view(png),
                                   "mimeType": "image/png"})
                    gl_textures.append({"source": len(images) - 1,
                                        "sampler": 0})
                    tex_out[tkey] = len(gl_textures) - 1
                mat["pbrMetallicRoughness"]["baseColorTexture"] = \
                    {"index": tex_out[tkey]}
            elif flat_colors and mdl is model and m2tex in flat_colors:
                # no texture to give this slot: a flat colour, not white
                mat["pbrMetallicRoughness"]["baseColorFactor"] = \
                    list(flat_colors[m2tex])
            if blend == 1:
                mat["alphaMode"] = "MASK"
                mat["alphaCutoff"] = 0.5
            elif blend >= 2:
                mat["alphaMode"] = "BLEND"
            if mflags & 0x04 or additive:
                mat["doubleSided"] = True
            materials_out.append(mat)
            prims.append({"attributes": dict(attrs), "indices": a_idx,
                          "material": len(materials_out) - 1})
        return prims

    primitives = build_primitives(model, skin, textures, True,
                                  allowed_geosets)

    # ------------------------------------------------------------- bones
    n_bones = len(model.bones)
    pivots = [_cv(b.pivot) for b in model.bones]
    pivots = [tuple(c * YARD for c in p) for p in pivots]
    nodes = []
    for i, b in enumerate(model.bones):
        pp = pivots[b.parent] if b.parent >= 0 else (0, 0, 0)
        t = tuple(pivots[i][k] - pp[k] for k in range(3))
        nodes.append({"name": f"bone{i}", "translation": list(t)})
    for i, b in enumerate(model.bones):
        if b.parent >= 0:
            nodes[b.parent].setdefault("children", []).append(i)
    roots = [i for i, b in enumerate(model.bones) if b.parent < 0]

    ibm = bytearray()
    for p in pivots:
        m = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, -p[0], -p[1], -p[2], 1]
        ibm += struct.pack("<16f", *m)
    a_ibm = acc(view(bytes(ibm)), 5126, n_bones, "MAT4")

    mesh_node = len(nodes)
    nodes.append({"name": model.name or "mesh", "mesh": 0, "skin": 0})
    meshes_out = [{"primitives": primitives, "name": model.name or "mesh"}]

    # rigid attached models (weapons) hung on attachment-point bones
    for att in attachments or []:
        point = next((a for a in model.attachments
                      if a["id"] == att["attach_id"]), None)
        if point is None:
            print(f"  attachment id {att['attach_id']} not on model, skipped")
            continue
        w_prims = build_primitives(att["model"], att["skin"],
                                   att["textures"], False)
        meshes_out.append({"primitives": w_prims,
                           "name": att["model"].name or "weapon"})
        bone = point["bone"]
        apos = tuple(c * YARD for c in _cv(point["pos"]))
        local = tuple(apos[k] - pivots[bone][k] for k in range(3))
        nodes.append({"name": f"attach{att['attach_id']}_{att['model'].name}",
                      "mesh": len(meshes_out) - 1,
                      "translation": list(local)})
        nodes[bone].setdefault("children", []).append(len(nodes) - 1)

    # -------------------------------------------------------- animations
    animations = []
    name_counts = {}
    for si, seq in enumerate(model.sequences):
        if seq_filter and seq.id not in seq_filter:
            continue
        di = model.resolve_alias(si)
        dur = model.sequences[di].duration
        if dur == 0:
            continue
        base = ANIM_NAMES.get(seq.id, f"anim{seq.id}")
        k = name_counts.get(base, 0)
        name_counts[base] = k + 1
        name = base if k == 0 else f"{base}.{k:03d}"

        samplers, channels = [], []

        def channel(node, path, times, values, fmt_per_key):
            t_blob = b"".join(struct.pack("<f", t) for t in times)
            a_t = acc(view(t_blob), 5126, len(times), "SCALAR",
                      min=[times[0]], max=[times[-1]])
            v_blob = b"".join(struct.pack(f"<{len(v)}f", *v) for v in values)
            a_v = acc(view(v_blob), 5126, len(values), fmt_per_key)
            samplers.append({"input": a_t, "output": a_v,
                             "interpolation": "LINEAR"})
            channels.append({"sampler": len(samplers) - 1,
                             "target": {"node": node, "path": path}})

        for bi, bone in enumerate(model.bones):
            rest_t = nodes[bi]["translation"]
            pp = pivots[bone.parent] if bone.parent >= 0 else (0, 0, 0)
            # translation
            times, vals = bone.trans.keys(model, di, "f", 3)
            if times and bone.trans.gseq >= 0:
                # global-sequence tracks run their own long timeline; baked
                # verbatim they stretch every clip (0.7s runs became 6.7s
                # with a long tail hold). Freeze them at their first pose.
                times, vals = [times[0]], [vals[0]]
            if times:
                ts = [t / 1000 for t in times]
                vs = []
                for v in vals:
                    c = _cv(v)
                    vs.append((pivots[bi][0] - pp[0] + c[0] * YARD,
                               pivots[bi][1] - pp[1] + c[1] * YARD,
                               pivots[bi][2] - pp[2] + c[2] * YARD))
                channel(bi, "translation", ts, vs, "VEC3")
            else:
                channel(bi, "translation", [0.0], [tuple(rest_t)], "VEC3")
            # rotation
            times, vals = bone.rot.keys(model, di, "H", 4)
            if times and bone.rot.gseq >= 0:
                times, vals = [times[0]], [vals[0]]
            if times:
                ts = [t / 1000 for t in times]
                vs = []
                prev = None
                for v in vals:
                    q = _cq(_decomp_quat(v))
                    if prev and sum(a * b for a, b in zip(q, prev)) < 0:
                        q = tuple(-c for c in q)
                    prev = q
                    vs.append(q)
                channel(bi, "rotation", ts, vs, "VEC4")
            else:
                channel(bi, "rotation", [0.0], [(0, 0, 0, 1)], "VEC4")
            # scale
            times, vals = bone.scale.keys(model, di, "f", 3)
            if times and bone.scale.gseq >= 0:
                times, vals = [times[0]], [vals[0]]
            if times:
                ts = [t / 1000 for t in times]
                vs = [(v[1], v[2], v[0]) for v in vals]
                channel(bi, "scale", ts, vs, "VEC3")
            else:
                channel(bi, "scale", [0.0], [(1, 1, 1)], "VEC3")

        animations.append({"name": name, "samplers": samplers,
                           "channels": channels})

    # ----------------------------------------------------------- assemble
    gltf = {
        "asset": {"version": "2.0", "generator": "warcraft-art pipeline"},
        "scene": 0,
        "scenes": [{"nodes": roots + [mesh_node]}],
        "nodes": nodes,
        "meshes": meshes_out,
        "skins": [{"joints": list(range(n_bones)),
                   "inverseBindMatrices": a_ibm}],
        "accessors": accessors,
        "bufferViews": views,
        "buffers": [{"byteLength": len(buf.data)}],
        "materials": materials_out,
        "samplers": [{"wrapS": 10497, "wrapT": 10497,
                      "magFilter": 9729, "minFilter": 9987}],
        "animations": animations,
    }
    if images:
        gltf["images"] = images
        gltf["textures"] = gl_textures

    js = json.dumps(gltf, separators=(",", ":")).encode()
    js += b" " * ((4 - len(js) % 4) % 4)
    bin_data = bytes(buf.data)
    bin_data += b"\0" * ((4 - len(bin_data) % 4) % 4)
    glb = (struct.pack("<III", 0x46546C67, 2, 28 + len(js) + len(bin_data))
           + struct.pack("<II", len(js), 0x4E4F534A) + js
           + struct.pack("<II", len(bin_data), 0x004E4942) + bin_data)
    with open(out_path, "wb") as f:
        f.write(glb)
    return {"animations": [a["name"] for a in animations],
            "bones": n_bones, "vertices": len(model.vertices),
            "primitives": len(primitives), "size": len(glb)}
