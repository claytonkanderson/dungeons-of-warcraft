"""Diablo II DCC (animated sprite) decoder -> list of directions, each a list of
frames of 8-bit palette-indexed pixel rows on a common per-direction canvas."""
import struct

_WIDTH_TABLE = [0, 1, 2, 4, 6, 8, 10, 12, 14, 16, 20, 24, 26, 28, 30, 32]
_PIXEL_MASK_LOOKUP = [0, 1, 1, 2, 1, 2, 2, 3, 1, 2, 2, 3, 2, 3, 3, 4]


class Bits:
    __slots__ = ('d', 'pos')

    def __init__(self, data, bitpos=0):
        self.d = data
        self.pos = bitpos

    def get(self, n):
        if n == 0:
            return 0
        pos = self.pos
        byte = pos >> 3
        sh = pos & 7
        nbytes = (sh + n + 7) >> 3
        v = (int.from_bytes(self.d[byte:byte + nbytes], 'little') >> sh) & ((1 << n) - 1)
        self.pos = pos + n
        return v

    def get_signed(self, n):
        v = self.get(n)
        if n and v & (1 << (n - 1)):
            v -= 1 << n
        return v

    def copy(self):
        return Bits(self.d, self.pos)

    def skip(self, n):
        self.pos += n

    def align(self):
        self.pos = (self.pos + 7) & ~7


class Frame:
    __slots__ = ('width', 'height', 'xoff', 'yoff', 'opt', 'coded', 'flip',
                 'xmin', 'ymin', 'xmax', 'ymax', 'cells', 'ncw', 'nch', 'pixels')


def _cell_layout(first, size):
    """Return list of cell sizes along one axis given the first cell size."""
    if size - first <= 1:
        return [size]
    tmp = size - first - 1
    n = 2 + tmp // 4
    if tmp % 4 == 0:
        n -= 1
    out = [first] + [4] * (n - 2)
    out.append(size - first - 4 * (n - 2))
    return out


def decode_direction(data, offset, nframes):
    bm = Bits(data, offset * 8)
    outsize = bm.get(32)
    flags = bm.get(2)
    v0b = _WIDTH_TABLE[bm.get(4)]
    wb = _WIDTH_TABLE[bm.get(4)]
    hb = _WIDTH_TABLE[bm.get(4)]
    xb = _WIDTH_TABLE[bm.get(4)]
    yb = _WIDTH_TABLE[bm.get(4)]
    ob = _WIDTH_TABLE[bm.get(4)]
    cb = _WIDTH_TABLE[bm.get(4)]

    frames = []
    dxmin = dymin = 1 << 30
    dxmax = dymax = -(1 << 30)
    total_opt = 0
    for _ in range(nframes):
        f = Frame()
        bm.get(v0b)
        f.width = bm.get(wb)
        f.height = bm.get(hb)
        f.xoff = bm.get_signed(xb)
        f.yoff = bm.get_signed(yb)
        f.opt = bm.get(ob)
        f.coded = bm.get(cb)
        f.flip = bm.get(1)
        f.xmin = f.xoff
        f.xmax = f.xoff + f.width - 1
        if f.flip:
            f.ymin = f.yoff
            f.ymax = f.yoff + f.height - 1
        else:
            f.ymax = f.yoff
            f.ymin = f.yoff - f.height + 1
        total_opt += f.opt
        frames.append(f)
        dxmin, dxmax = min(dxmin, f.xmin), max(dxmax, f.xmax)
        dymin, dymax = min(dymin, f.ymin), max(dymax, f.ymax)
    if total_opt:
        bm.align()
        bm.skip(total_opt * 8)

    dw = dxmax - dxmin + 1
    dh = dymax - dymin + 1

    ec_size = bm.get(20) if flags & 2 else 0
    pm_size = bm.get(20)
    et_size = rp_size = 0
    if flags & 1:
        et_size = bm.get(20)
        rp_size = bm.get(20)
    palette = []
    for i in range(256):
        if bm.get(1):
            palette.append(i)

    ec = bm.copy(); bm.skip(ec_size)
    pm = bm.copy(); bm.skip(pm_size)
    et = bm.copy(); bm.skip(et_size)
    rp = bm.copy(); bm.skip(rp_size)
    pcd = bm.copy()

    # direction cells
    ncw = 1 + (dw - 1) // 4
    nch = 1 + (dh - 1) // 4

    # frame cells
    for f in frames:
        ws = _cell_layout(4 - ((f.xmin - dxmin) % 4), f.width)
        hs = _cell_layout(4 - ((f.ymin - dymin) % 4), f.height)
        f.ncw, f.nch = len(ws), len(hs)
        cells = []
        oy = f.ymin - dymin
        for ch in hs:
            ox = f.xmin - dxmin
            for cw in ws:
                cells.append((ox, oy, cw, ch))
                ox += cw
            oy += ch
        f.cells = cells

    # ---- stage 1: pixel buffer ----
    pixel_buffer = []  # entries: [v0,v1,v2,v3, frame, cellidx]
    cell_buffer = [None] * (ncw * nch)
    for fi, f in enumerate(frames):
        ocx = (f.xmin - dxmin) // 4
        ocy = (f.ymin - dymin) // 4
        for cy in range(f.nch):
            ccy = cy + ocy
            for cx in range(f.ncw):
                cur = ocx + cx + ccy * ncw
                old = cell_buffer[cur]
                if old is not None:
                    tmp = ec.get(1) if ec_size > 0 else 0
                    if tmp:
                        continue
                    mask = pm.get(4)
                else:
                    mask = 0x0F
                stack = [0, 0, 0, 0]
                last = 0
                nbits = _PIXEL_MASK_LOOKUP[mask]
                enc = et.get(1) if (nbits and et_size > 0) else 0
                decoded = 0
                for i in range(nbits):
                    if enc:
                        stack[i] = rp.get(8)
                    else:
                        v = last
                        d = pcd.get(4)
                        v += d
                        while d == 15:
                            d = pcd.get(4)
                            v += d
                        stack[i] = v
                    if stack[i] == last:
                        stack[i] = 0
                        break
                    last = stack[i]
                    decoded += 1
                entry = [0, 0, 0, 0, fi, cx + cy * f.ncw]
                idx = decoded - 1
                for i in range(4):
                    if mask & (1 << i):
                        if idx >= 0:
                            entry[i] = stack[idx]
                            idx -= 1
                        else:
                            entry[i] = 0
                    else:
                        entry[i] = old[i]
                cell_buffer[cur] = entry
                pixel_buffer.append(entry)
    npal = len(palette)
    for e in pixel_buffer:
        for i in range(4):
            e[i] = palette[e[i]] if e[i] < npal else 0

    # ---- stage 2: frames ----
    canvas = bytearray(dw * dh)
    dir_cells = [[-1, -1, 0, 0] for _ in range(ncw * nch)]  # lastw, lasth, xoff, yoff
    pb = 0
    npb = len(pixel_buffer)
    out_frames = []
    for fi, f in enumerate(frames):
        img = bytearray(dw * dh)
        for c, (ox, oy, cw, ch) in enumerate(f.cells):
            bc = dir_cells[(ox // 4) + (oy // 4) * ncw]
            e = pixel_buffer[pb] if pb < npb else None
            if e is None or e[4] != fi or e[5] != c:
                if cw != bc[0] or ch != bc[1]:
                    for y in range(ch):
                        s = ox + (oy + y) * dw
                        canvas[s:s + cw] = bytes(cw)
                else:
                    bx, by = bc[2], bc[3]
                    rows = [bytes(canvas[bx + (by + y) * dw: bx + (by + y) * dw + cw]) for y in range(ch)]
                    for y in range(ch):
                        s = ox + (oy + y) * dw
                        canvas[s:s + cw] = rows[y]
                        img[s:s + cw] = rows[y]
            else:
                if e[0] == e[1]:
                    row = bytes([e[0]]) * cw
                    for y in range(ch):
                        s = ox + (oy + y) * dw
                        canvas[s:s + cw] = row
                        img[s:s + cw] = row
                else:
                    nb = 2 if e[1] != e[2] else 1
                    for y in range(ch):
                        s = ox + (oy + y) * dw
                        row = bytes(e[pcd.get(nb)] for _ in range(cw))
                        canvas[s:s + cw] = row
                        img[s:s + cw] = row
                pb += 1
            bc[0], bc[1], bc[2], bc[3] = cw, ch, ox, oy
        out_frames.append(img)
    return {'width': dw, 'height': dh, 'xmin': dxmin, 'ymin': dymin, 'frames': out_frames,
            'frame_boxes': [(f.xmin, f.ymin, f.width, f.height) for f in frames]}


def decode(data):
    sig, ver, ndir = data[0], data[1], data[2]
    if sig != 0x74:
        raise ValueError('not a DCC')
    nframes, = struct.unpack_from('<I', data, 3)
    offsets = struct.unpack_from('<%dI' % ndir, data, 15)
    return [decode_direction(data, off, nframes) for off in offsets]
