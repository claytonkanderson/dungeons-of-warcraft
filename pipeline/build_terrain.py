"""Bake a dungeon's outdoor ADT terrain into per-tile GLBs with
splat-blended textures, plus a water mesh from MH2O. build_for() is the
live entry point, called per dungeon; main() is a Deadmines-only probe.

Coordinates ride the same empirically calibrated world -> main-WMO-local ->
Godot transform as dungeon_common.py (calibration block reproduced).
MCNK positions were probed to be server-space (x north, y west, z up), so
they feed straight into that transform. Alpha maps are decided per layer
(RLE-compressed flag, else 4096 = 8-bit, else 2048 = 4-bit). Shading is
baked from MCNR up-normals (slope darkening) since these tiles carry no
vertex colors.
"""
import json
import math
import re
import struct
from pathlib import Path

import numpy as np

from config import OUT, AC
from casc import Storage
from wmo import WMORoot, chunks_of
from blp import decode_blp, write_png
from gltf_export import YARD

MAP_CENTER = 32 * 533.33333
MAIN_FDID = 108483
TILE = 533.33333
CHUNK = TILE / 16.0
UNIT = CHUNK / 8.0
BAKE = 128           # baked pixels per chunk edge (atlas 2048 per tile)
REPEATS = 4.0        # ground texture repeats per chunk edge


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


def calibrate(s):
    """Identical brute-force calibration to dungeon_common.calibrate."""
    spawns = load_spawns()
    wdt = s.read_fdid(780605)
    c = chunks_of(wdt)
    main, maid = c[b"MAIN"], c[b"MAID"]
    placements = {}
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
            placements[uid] = {"fdid": nid, "pos": pos, "rot": rot}
    main_pl = next(p for p in placements.values() if p["fdid"] == MAIN_FDID)
    ox, oy, oz = world_from_file(*main_pl["pos"])
    ry_main = main_pl["rot"][1]
    root = WMORoot(s.read_fdid(MAIN_FDID))
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
    print(f"calibration: {hits}/{len(spawns)} spawns inside, yaw={deg:.1f}")
    return (ox, oy, oz), mat


def top_chunks(buf):
    out = []
    p = 0
    while p + 8 <= len(buf):
        cid = buf[p:p + 4][::-1]
        size = int.from_bytes(buf[p + 4:p + 8], "little")
        out.append((cid, buf[p + 8:p + 8 + size]))
        p += 8 + size
    return out


def decode_alpha(mcal, offset, compressed):
    """One 64x64 alpha map starting at `offset` in the MCAL blob."""
    if compressed:
        out = bytearray()
        p = offset
        while len(out) < 4096 and p < len(mcal):
            ctrl = mcal[p]
            p += 1
            n = ctrl & 0x7F
            if ctrl & 0x80:
                out += bytes([mcal[p]]) * n
                p += 1
            else:
                out += mcal[p:p + n]
                p += n
        out = (out + bytes(4096))[:4096]
        return np.frombuffer(bytes(out), dtype=np.uint8).reshape(64, 64)
    if len(mcal) - offset >= 4096:
        return np.frombuffer(mcal[offset:offset + 4096],
                             dtype=np.uint8).reshape(64, 64)
    # 2048-byte 4-bit
    raw = np.frombuffer(mcal[offset:offset + 2048], dtype=np.uint8)
    lo = (raw & 0x0F) * 17
    hi = (raw >> 4) * 17
    return np.stack([lo, hi], axis=1).reshape(64, 64)


def bilinear9(grid9, size):
    idx = np.linspace(0.0, 8.0, size)
    i0 = np.floor(idx).astype(int)
    i1 = np.minimum(i0 + 1, 8)
    f = idx - i0
    a = grid9[i0, :] * (1 - f)[:, None] + grid9[i1, :] * f[:, None]
    return a[:, i0] * (1 - f)[None, :] + a[:, i1] * f[None, :]


class GlbWriter:
    def __init__(self):
        self.bin = bytearray()
        self.views = []
        self.accessors = []

    def view(self, data, target=None):
        while len(self.bin) % 4:
            self.bin += b"\0"
        v = {"buffer": 0, "byteOffset": len(self.bin), "byteLength": len(data)}
        if target:
            v["target"] = target
        self.bin += data
        self.views.append(v)
        return len(self.views) - 1

    def acc(self, vi, ctype, count, atype, mn=None, mx=None):
        a = {"bufferView": vi, "componentType": ctype, "count": count,
             "type": atype}
        if mn is not None:
            a["min"] = mn
            a["max"] = mx
        self.accessors.append(a)
        return len(self.accessors) - 1

    def write(self, path, positions, uvs, indices, png=None, color=None):
        pos = np.asarray(positions, dtype=np.float32)
        a_pos = self.acc(self.view(pos.tobytes(), 34962), 5126, len(pos),
                         "VEC3", pos.min(axis=0).tolist(),
                         pos.max(axis=0).tolist())
        attrs = {"POSITION": a_pos}
        if uvs is not None:
            uv = np.asarray(uvs, dtype=np.float32)
            attrs["TEXCOORD_0"] = self.acc(self.view(uv.tobytes(), 34962),
                                           5126, len(uv), "VEC2")
        idx = np.asarray(indices, dtype=np.uint32)
        a_idx = self.acc(self.view(idx.tobytes(), 34963), 5125, len(idx),
                         "SCALAR")
        mat = {"pbrMetallicRoughness": {"metallicFactor": 0.0,
                                        "roughnessFactor": 1.0},
               "doubleSided": True,
               "extensions": {"KHR_materials_unlit": {}}}
        gltf = {"asset": {"version": "2.0", "generator": "dungeons-of-warcraft"},
                "extensionsUsed": ["KHR_materials_unlit"],
                "scene": 0, "scenes": [{"nodes": [0]}],
                "nodes": [{"name": path.stem, "mesh": 0}],
                "meshes": [{"primitives": [{"attributes": attrs,
                                            "indices": a_idx, "material": 0}]}],
                "materials": [mat],
                "accessors": self.accessors, "bufferViews": self.views,
                "buffers": [{"byteLength": 0}]}
        if png is not None:
            iv = self.view(png)
            gltf["images"] = [{"bufferView": iv, "mimeType": "image/png"}]
            gltf["samplers"] = [{"wrapS": 33071, "wrapT": 33071,
                                 "minFilter": 9987, "magFilter": 9729}]
            gltf["textures"] = [{"source": 0, "sampler": 0}]
            mat["pbrMetallicRoughness"]["baseColorTexture"] = {"index": 0}
        if color is not None:
            mat["pbrMetallicRoughness"]["baseColorFactor"] = color
            if color[3] < 1.0:
                mat["alphaMode"] = "BLEND"
        gltf["buffers"][0]["byteLength"] = len(self.bin)
        js = json.dumps(gltf).encode()
        js += b" " * (-len(js) % 4)
        bd = bytes(self.bin) + b"\0" * (-len(self.bin) % 4)
        glb = (struct.pack("<III", 0x46546C67, 2, 28 + len(js) + len(bd))
               + struct.pack("<II", len(js), 0x4E4F534A) + js
               + struct.pack("<II", len(bd), 0x004E4942) + bd)
        path.write_bytes(glb)
        return len(glb)


def build_for(s, wdt_fdid, to_gl, out_dir, tile_keep=None):
    """Bake every ADT tile of one map. No-op for global-WMO maps.
    tile_keep(x, y): optional predicate over server world coordinates; a
    tile is baked when any of its corners or its centre passes (a wing of
    a multi-instance map bakes only the ground around its own building)."""
    wdt = s.read_fdid(wdt_fdid)
    c = chunks_of(wdt)
    if b"MAIN" not in c or b"MAID" not in c:
        print("terrain: no ADT tiles (global-WMO map), skipping")
        return
    main_c, maid = c[b"MAIN"], c[b"MAID"]
    n_tiles = sum(1 for i in range(4096)
                  if int.from_bytes(main_c[i * 8:i * 8 + 4], "little") & 1)
    if n_tiles == 0:
        print("terrain: no ADT tiles flagged, skipping")
        return
    if (out_dir / "terrain.json").exists():
        print("terrain: cached (delete the terrain dir to rebake)")
        return
    out_dir.mkdir(parents=True, exist_ok=True)

    tex_cache = {}

    def texture(fdid):
        if fdid not in tex_cache:
            w, h, rgba = decode_blp(s.read_fdid(fdid))
            arr = np.frombuffer(rgba, dtype=np.uint8).reshape(h, w, 4)
            tex_cache[fdid] = arr[:, :, :3].astype(np.float32)
        return tex_cache[fdid]

    # texture sample coords for one baked chunk (nearest, tiled)
    frac = ((np.arange(BAKE) + 0.5) / BAKE * REPEATS) % 1.0

    manifest = {"tiles": [], "water": ""}
    water_pos = []
    water_idx = []
    tiles_done = 0
    for ti in range(64 * 64):
        if not int.from_bytes(main_c[ti * 8:ti * 8 + 4], "little") & 1:
            continue
        col, row = ti % 64, ti // 64
        if tile_keep is not None:
            # tile (col, row) spans world x (north) in [c - (row+1)T, c - row T]
            # and y (west) in [c - (col+1)T, c - col T], c = MAP_CENTER
            xs = (MAP_CENTER - (row + 1) * TILE, MAP_CENTER - row * TILE)
            ys = (MAP_CENTER - (col + 1) * TILE, MAP_CENTER - col * TILE)
            probes = [(x, y) for x in xs for y in ys] \
                + [(sum(xs) / 2, sum(ys) / 2)]
            if not any(tile_keep(x, y) for x, y in probes):
                continue
        e = struct.unpack_from("<8I", maid, ti * 32)
        root = s.read_fdid(e[0])
        rc = top_chunks(root)
        mcnks = [d for cid, d in rc if cid == b"MCNK"]
        tex0 = s.read_fdid(e[3]) if e[3] else b""
        tc = top_chunks(tex0)
        tex_mcnks = [d for cid, d in tc if cid == b"MCNK"]
        mdid = next((d for cid, d in tc if cid == b"MDID"), b"")
        tex_fdids = list(struct.unpack(f"<{len(mdid)//4}I", mdid))

        atlas = np.zeros((16 * BAKE, 16 * BAKE, 3), dtype=np.float32)
        positions = []
        uvs = []
        indices = []
        for k, hdr in enumerate(mcnks):
            flags, ix, iy = struct.unpack_from("<3I", hdr, 0)
            px, py, pz = struct.unpack_from("<3f", hdr, 0x68)
            holes = 0
            if flags & 0x10000:
                holes = struct.unpack_from("<Q", hdr, 0x14)[0]
            else:
                lo = struct.unpack_from("<H", hdr, 0x3C)[0]
                for hy in range(4):
                    for hx in range(4):
                        if lo & (1 << (hy * 4 + hx)):
                            for sy in range(2):
                                for sx in range(2):
                                    holes |= 1 << ((hy * 2 + sy) * 8
                                                   + (hx * 2 + sx))
            sub = {cid: d for cid, d in top_chunks(hdr[128:])}
            if b"MCVT" not in sub:
                continue
            hts = np.frombuffer(sub[b"MCVT"][:580], dtype=np.float32)
            nrm = np.frombuffer(sub.get(b"MCNR", bytes(448))[:435],
                                dtype=np.int8).astype(np.float32)

            # ---------------- mesh vertices (17 interleaved rows)
            base = len(positions)
            row_starts = []
            vi = 0
            for j in range(17):
                row_starts.append(base + vi)
                ncol = 9 if j % 2 == 0 else 8
                for i in range(ncol):
                    off = (i + (0.5 if j % 2 else 0.0)) * UNIT
                    wx = px - j * UNIT * 0.5
                    wy = py - off
                    wz = pz + float(hts[vi])
                    positions.append(to_gl(wx, wy, wz))
                    u = (ix + (off / CHUNK)) / 16.0
                    v = (iy + (j / 16.0)) / 16.0
                    uvs.append((u, v))
                    vi += 1
            for r in range(8):
                for cc in range(8):
                    if holes & (1 << (r * 8 + cc)):
                        continue
                    A = row_starts[r * 2] + cc
                    B = A + 1
                    C = row_starts[r * 2 + 2] + cc
                    D = C + 1
                    M = row_starts[r * 2 + 1] + cc
                    indices += [A, B, M, B, D, M, D, C, M, C, A, M]

            # ---------------- baked splat texture
            layers = []
            if k < len(tex_mcnks):
                tsub = {cid: d for cid, d in top_chunks(tex_mcnks[k])}
                mcly = tsub.get(b"MCLY", b"")
                mcal = tsub.get(b"MCAL", b"")
                for li in range(len(mcly) // 16):
                    tid, lflags, aofs, _eff = struct.unpack_from(
                        "<IIIi", mcly, li * 16)
                    layers.append((tid, lflags, aofs))
            out = None
            for li, (tid, lflags, aofs) in enumerate(layers):
                if tid >= len(tex_fdids):
                    continue
                try:
                    t = texture(tex_fdids[tid])
                except Exception:
                    continue
                th, tw = t.shape[0], t.shape[1]
                samp = t[(frac * th).astype(int)[:, None],
                         (frac * tw).astype(int)[None, :]]
                if out is None or li == 0:
                    out = samp.copy()
                else:
                    a = decode_alpha(mcal, aofs, bool(lflags & 0x200))
                    a = a.astype(np.float32) / 255.0
                    if BAKE != 64:
                        a = np.kron(a, np.ones((BAKE // 64, BAKE // 64)))
                    out = out * (1.0 - a[:, :, None]) + samp * a[:, :, None]
            if out is None:
                out = np.full((BAKE, BAKE, 3), 90.0, dtype=np.float32)
            # slope shading from MCNR up component (every 3rd byte, outer 9x9)
            nz = np.zeros((9, 9), dtype=np.float32)
            vi = 0
            for j in range(17):
                ncol = 9 if j % 2 == 0 else 8
                if j % 2 == 0:
                    for i in range(ncol):
                        nz[j // 2, i] = nrm[(vi + i) * 3 + 2] / 127.0
                vi += ncol
            shade = 0.55 + 0.45 * np.clip(bilinear9(nz, BAKE), 0.0, 1.0)
            out = out * shade[:, :, None]
            atlas[iy * BAKE:(iy + 1) * BAKE, ix * BAKE:(ix + 1) * BAKE] = out

            # ---------------- water (MH2O handled per tile below needs px/py)
        # MH2O
        mh2o = next((d for cid, d in rc if cid == b"MH2O"), b"")
        if mh2o:
            for ck in range(256):
                ofs_i, n_layers, _oa = struct.unpack_from("<III", mh2o, ck * 12)
                if not n_layers:
                    continue
                cix, ciy = ck % 16, ck // 16
                # chunk NW corner in world coords
                cpx = (32 - row) * TILE - ciy * CHUNK
                cpy = (32 - col) * TILE - cix * CHUNK
                for li in range(n_layers):
                    io = ofs_i + li * 24
                    (ltype, lvf, hmin, hmax, xo, yo, w, h, obm,
                     ovd) = struct.unpack_from("<HHffBBBBII", mh2o, io)
                    bits = None
                    if obm:
                        nb = (w * h + 7) // 8
                        bits = mh2o[obm:obm + nb]
                    for cy in range(h):
                        for cx in range(w):
                            cell = cy * w + cx
                            if bits and not (bits[cell // 8] >> (cell % 8)) & 1:
                                continue
                            wx0 = cpx - (yo + cy) * UNIT
                            wy0 = cpy - (xo + cx) * UNIT
                            b0 = len(water_pos)
                            for (dx, dy) in ((0, 0), (0, 1), (1, 1), (1, 0)):
                                water_pos.append(to_gl(wx0 - dx * UNIT,
                                                       wy0 - dy * UNIT, hmin))
                            water_idx += [b0, b0 + 1, b0 + 2,
                                          b0, b0 + 2, b0 + 3]

        png = write_png(16 * BAKE, 16 * BAKE, _rgba(atlas))
        w = GlbWriter()
        dest = out_dir / f"t{col}_{row}.glb"
        size = w.write(dest, positions, uvs, indices, png=png)
        manifest["tiles"].append(dest.name)
        tiles_done += 1
        print(f"tile {col},{row}: {len(positions)} verts, "
              f"{len(indices)//3} tris, {size//1024} KB")

    if water_pos:
        w = GlbWriter()
        dest = out_dir / "water.glb"
        size = w.write(dest, water_pos, None, water_idx,
                       color=[0.09, 0.22, 0.30, 0.62])
        manifest["water"] = dest.name
        print(f"water: {len(water_pos)//4} cells, {size//1024} KB")

    (out_dir / "terrain.json").write_text(json.dumps(manifest, indent=1))
    print(f"{tiles_done} tiles written to {out_dir}")


def _rgba(atlas):
    a = np.clip(atlas, 0, 255).astype(np.uint8)
    rgba = np.dstack([a, np.full(a.shape[:2], 255, dtype=np.uint8)])
    return rgba.tobytes()


def main():
    s = Storage()
    (ox, oy, oz), mat = calibrate(s)

    def to_gl(wx, wy, wz):
        dn, dw = wx - ox, wy - oy
        xl = mat[0][0] * dn + mat[0][1] * dw
        yl = mat[1][0] * dn + mat[1][1] * dw
        return (-yl * YARD, (wz - oz) * YARD, -xl * YARD)

    build_for(s, 780605, to_gl, OUT / "deadmines" / "terrain")


if __name__ == "__main__":
    main()
