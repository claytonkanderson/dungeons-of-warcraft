"""Parser for WMO root + group files (modern v17, fdid-based).

Covers what a static walkthrough export needs: materials, group
geometry (verts/normals/uvs/vertex colors), render batches, doodad
placements, and group bounding boxes. Portals/BSP/fog are skipped.
"""
import struct


def chunks_of(data, multi=False):
    out = {}
    pos = 0
    while pos + 8 <= len(data):
        cid = data[pos:pos + 4][::-1]  # stored reversed
        size = int.from_bytes(data[pos + 4:pos + 8], "little")
        body = data[pos + 8:pos + 8 + size]
        if multi:
            out.setdefault(cid, []).append(body)
        else:
            out.setdefault(cid, body)
        pos += 8 + size
    return out


class WMORoot:
    def __init__(self, data: bytes):
        c = chunks_of(data)
        (self.n_materials, self.n_groups, self.n_portals, self.n_lights,
         self.n_doodad_names, self.n_doodad_defs, self.n_doodad_sets,
         self.ambient) = struct.unpack_from("<8I", c[b"MOHD"], 0)
        self.flags = struct.unpack_from("<H", c[b"MOHD"], 60)[0] \
            if len(c[b"MOHD"]) >= 62 else 0

        # materials: 64 bytes each; texture fields are fdids in modern files
        self.materials = []
        momt = c[b"MOMT"]
        for i in range(self.n_materials):
            f = struct.unpack_from("<16I", momt, i * 64)
            self.materials.append({
                "flags": f[0], "shader": f[1], "blend": f[2],
                "texture1": f[3], "texture2": f[6], "texture3": f[9],
            })

        names = c.get(b"MOGN", b"")
        self.group_names = []
        mogi = c[b"MOGI"]
        for i in range(self.n_groups):
            gflags = struct.unpack_from("<I", mogi, i * 32)[0]
            bbox = struct.unpack_from("<6f", mogi, i * 32 + 4)
            name_ofs = struct.unpack_from("<i", mogi, i * 32 + 28)[0]
            name = ""
            if 0 <= name_ofs < len(names):
                name = names[name_ofs:names.index(b"\0", name_ofs)] \
                    .decode("utf-8", "replace")
            self.group_names.append({"flags": gflags, "bbox": bbox,
                                     "name": name})

        gfid = c.get(b"GFID", b"")
        all_gfid = struct.unpack(f"<{len(gfid)//4}I", gfid)
        self.group_fdids = list(all_gfid[:self.n_groups])

        # doodads
        modi = c.get(b"MODI", b"")
        self.doodad_fdids = list(struct.unpack(f"<{len(modi)//4}I", modi))
        self.doodad_sets = []
        mods = c.get(b"MODS", b"")
        for i in range(len(mods) // 32):
            nm = mods[i*32:i*32+20].rstrip(b"\0").decode("ascii", "?")
            st, n = struct.unpack_from("<II", mods, i * 32 + 20)
            self.doodad_sets.append({"name": nm, "start": st, "count": n})
        self.doodad_defs = []
        modd = c.get(b"MODD", b"")
        for i in range(len(modd) // 40):
            o = i * 40
            packed = struct.unpack_from("<I", modd, o)[0]
            name_index = packed & 0xFFFFFF          # index into MODI
            dflags = packed >> 24
            pos = struct.unpack_from("<3f", modd, o + 4)
            rot = struct.unpack_from("<4f", modd, o + 16)  # quat x,y,z,w
            scale = struct.unpack_from("<f", modd, o + 32)[0]
            color = struct.unpack_from("<4B", modd, o + 36)  # BGRA
            self.doodad_defs.append({"index": name_index, "flags": dflags,
                                     "pos": pos, "rot": rot, "scale": scale,
                                     "color": color})

        # lights (48 bytes each) — enough to place point lights later
        self.lights = []
        molt = c.get(b"MOLT", b"")
        for i in range(len(molt) // 48):
            o = i * 48
            ltype = molt[o]
            b, g, r, a = struct.unpack_from("<4B", molt, o + 4)
            pos = struct.unpack_from("<3f", molt, o + 8)
            intensity = struct.unpack_from("<f", molt, o + 20)[0]
            att0, att1 = struct.unpack_from("<2f", molt, o + 40)
            self.lights.append({"type": ltype, "color": (r, g, b),
                                "pos": pos, "intensity": intensity,
                                "atten": (att0, att1)})


GROUP_HAS_VCOLOR = 0x4
GROUP_EXTERIOR = 0x8
GROUP_EXTERIOR_LIT = 0x40


class WMOGroup:
    def __init__(self, data: bytes):
        outer = chunks_of(data)
        mogp = outer[b"MOGP"]
        (self.name_ofs, self.desc_ofs, self.flags) = \
            struct.unpack_from("<3I", mogp, 0)
        self.bbox = struct.unpack_from("<6f", mogp, 12)
        (self.trans_batches, self.int_batches, self.ext_batches) = \
            struct.unpack_from("<3H", mogp, 40)
        sub = chunks_of(mogp[68:], multi=True)

        movt = sub.get(b"MOVT", [b""])[0]
        n = len(movt) // 12
        self.vertices = [struct.unpack_from("<3f", movt, i * 12)
                         for i in range(n)]
        monr = sub.get(b"MONR", [b""])[0]
        self.normals = [struct.unpack_from("<3f", monr, i * 12)
                        for i in range(n)] if monr else [(0, 0, 1)] * n
        motv = sub.get(b"MOTV", [b""])[0]
        self.uvs = [struct.unpack_from("<2f", motv, i * 8)
                    for i in range(n)] if motv else [(0, 0)] * n
        mocv = sub.get(b"MOCV", [None])[0]
        self.colors = None
        if mocv:
            self.colors = [struct.unpack_from("<4B", mocv, i * 4)
                           for i in range(n)]  # BGRA

        movi = sub.get(b"MOVI", [b""])[0]
        self.indices = list(struct.unpack(f"<{len(movi)//2}H", movi))

        self.batches = []
        moba = sub.get(b"MOBA", [b""])[0]
        for i in range(len(moba) // 24):
            o = i * 24
            start = struct.unpack_from("<I", moba, o + 12)[0]
            count, mn, mx = struct.unpack_from("<3H", moba, o + 16)
            material = moba[o + 23]
            self.batches.append({"start": start, "count": count,
                                 "material": material})
