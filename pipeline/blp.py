"""BLP2 -> RGBA decode + minimal PNG writer. Stdlib only."""
import struct
import zlib


def _rgb565(c):
    r = (c >> 11) & 0x1F
    g = (c >> 5) & 0x3F
    b = c & 0x1F
    return ((r * 255 + 15) // 31, (g * 255 + 31) // 63, (b * 255 + 15) // 31)


def _decode_dxt_color(block, four_color):
    c0, c1 = struct.unpack_from("<HH", block, 0)
    bits = struct.unpack_from("<I", block, 4)[0]
    p0, p1 = _rgb565(c0), _rgb565(c1)
    pal = [p0 + (255,), p1 + (255,)]
    if four_color or c0 > c1:
        pal.append(tuple((2 * a + b) // 3 for a, b in zip(p0, p1)) + (255,))
        pal.append(tuple((a + 2 * b) // 3 for a, b in zip(p0, p1)) + (255,))
    else:
        pal.append(tuple((a + b) // 2 for a, b in zip(p0, p1)) + (255,))
        pal.append((0, 0, 0, 0))
    return [pal[(bits >> (2 * i)) & 3] for i in range(16)]


def decode_blp(data: bytes):
    """-> (width, height, rgba bytes)"""
    if data[:4] != b"BLP2":
        raise ValueError("not BLP2")
    compression = data[8]
    alpha_depth = data[9]
    alpha_type = data[10]
    w, h = struct.unpack_from("<II", data, 12)
    mip_ofs = struct.unpack_from("<16I", data, 20)
    mip_len = struct.unpack_from("<16I", data, 84)
    src = data[mip_ofs[0]:mip_ofs[0] + mip_len[0]]
    out = bytearray(w * h * 4)

    if compression == 1:  # palettized
        pal = [struct.unpack_from("<BBBB", data, 148 + i * 4) for i in range(256)]
        for i in range(w * h):
            b, g, r, _ = pal[src[i]]
            out[i * 4:i * 4 + 3] = bytes((r, g, b))
        if alpha_depth == 0:
            for i in range(w * h):
                out[i * 4 + 3] = 255
        elif alpha_depth == 8:
            a = src[w * h:]
            for i in range(w * h):
                out[i * 4 + 3] = a[i]
        elif alpha_depth == 1:
            a = src[w * h:]
            for i in range(w * h):
                out[i * 4 + 3] = 255 if a[i // 8] & (1 << (i % 8)) else 0
        elif alpha_depth == 4:
            a = src[w * h:]
            for i in range(w * h):
                nib = (a[i // 2] >> (4 * (i % 2))) & 0xF
                out[i * 4 + 3] = nib * 17
    elif compression == 2:  # DXT
        if alpha_depth <= 1:
            mode = "dxt1"
        elif alpha_type == 7:
            mode = "dxt5"
        else:
            mode = "dxt3"
        bw = (w + 3) // 4
        bsize = 8 if mode == "dxt1" else 16
        for by in range((h + 3) // 4):
            for bx in range(bw):
                block = src[(by * bw + bx) * bsize:(by * bw + bx) * bsize + bsize]
                if mode == "dxt1":
                    px = _decode_dxt_color(block, False)
                elif mode == "dxt3":
                    px = _decode_dxt_color(block[8:], True)
                    for i in range(16):
                        nib = (block[i // 2] >> (4 * (i % 2))) & 0xF
                        px[i] = px[i][:3] + (nib * 17,)
                else:  # dxt5
                    px = _decode_dxt_color(block[8:], True)
                    a0, a1 = block[0], block[1]
                    abits = int.from_bytes(block[2:8], "little")
                    apal = [a0, a1]
                    if a0 > a1:
                        apal += [((7 - i) * a0 + i * a1) // 7 for i in range(1, 7)]
                    else:
                        apal += [((5 - i) * a0 + i * a1) // 5 for i in range(1, 5)]
                        apal += [0, 255]
                    for i in range(16):
                        px[i] = px[i][:3] + (apal[(abits >> (3 * i)) & 7],)
                for i, (r, g, b, a) in enumerate(px):
                    x, y = bx * 4 + i % 4, by * 4 + i // 4
                    if x < w and y < h:
                        o = (y * w + x) * 4
                        out[o:o + 4] = bytes((r, g, b, a))
    elif compression == 3:  # raw BGRA
        for i in range(w * h):
            b, g, r, a = src[i * 4:i * 4 + 4]
            out[i * 4:i * 4 + 4] = bytes((r, g, b, a))
    else:
        raise ValueError(f"BLP compression {compression}")
    return w, h, bytes(out)


def write_png(w, h, rgba: bytes) -> bytes:
    def chunk(tag, payload):
        c = tag + payload
        return struct.pack(">I", len(payload)) + c + struct.pack(">I", zlib.crc32(c))

    raw = b"".join(b"\x00" + rgba[y * w * 4:(y + 1) * w * 4] for y in range(h))
    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 9))
            + chunk(b"IEND", b""))


def blp_to_png(data: bytes) -> bytes:
    return write_png(*decode_blp(data))
