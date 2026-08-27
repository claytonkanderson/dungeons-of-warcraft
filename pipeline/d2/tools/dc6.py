"""Diablo II DC6 decoder -> same structure as dcc.decode (per-direction canvases)."""
import struct


def decode(data):
    ver, flags, enc = struct.unpack_from('<iii', data, 0)
    ndirs, nframes = struct.unpack_from('<ii', data, 16)
    ptrs = struct.unpack_from('<%dI' % (ndirs * nframes), data, 24)
    out = []
    for d in range(ndirs):
        frames = []
        boxes = []
        for f in range(nframes):
            off = ptrs[d * nframes + f]
            flip, w, h, ox, oy, _, _, length = struct.unpack_from('<iiiiiiii', data, off)
            px = data[off + 32: off + 32 + length]
            img = bytearray(w * h)
            x, y = 0, (0 if flip else h - 1)
            i = 0
            while i < len(px):
                b = px[i]; i += 1
                if b == 0x80:
                    x = 0
                    y += 1 if flip else -1
                elif b & 0x80:
                    x += b & 0x7F
                else:
                    img[y * w + x: y * w + x + b] = px[i:i + b]
                    i += b
                    x += b
            xmin = ox
            ymax = oy
            ymin = oy - h + 1
            boxes.append((xmin, ymin, w, h, bytes(img)))
        dxmin = min(b[0] for b in boxes)
        dymin = min(b[1] for b in boxes)
        dxmax = max(b[0] + b[2] for b in boxes)
        dymax = max(b[1] + b[3] for b in boxes)
        dw, dh = dxmax - dxmin, dymax - dymin
        canv_frames = []
        for (xmin, ymin, w, h, img) in boxes:
            canvas = bytearray(dw * dh)
            for yy in range(h):
                s = (ymin - dymin + yy) * dw + (xmin - dxmin)
                canvas[s:s + w] = img[yy * w:yy * w + w]
            canv_frames.append(bytes(canvas))
        out.append({'width': dw, 'height': dh, 'xmin': dxmin, 'ymin': dymin,
                    'frames': canv_frames})
    return out
