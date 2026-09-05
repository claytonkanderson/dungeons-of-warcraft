"""Export D2 fonts and item-stat display data.

- font16 atlas + per-glyph metrics (DC6 glyphs + Woo! width table)
- props_display.json: Properties.txt property -> stat list
- statdesc.json: ItemStatCost.txt display templates with tbl-resolved strings
"""
import os
import json
import struct
import config
import tbl as tbllib
from sprites import mpqs
from export_items import read_table  # reuse the table reader
from PIL import Image


def export_font(name='font16'):
    """One D2 bitmap font -> a 16x16 glyph atlas PNG + metrics JSON.

    Glyph pixels are palette indices along a ramp from near-black to light
    grey: the dark values are the stroke's outline and soft edge, and D2
    tints the ramp per text colour. The atlas keeps that ramp as alpha on a
    white glyph (brightest palette value = opaque), so a tinted label keeps
    its edges instead of turning into a solid blob."""
    m = mpqs()
    data = m.read('data\\local\\font\\latin\\%s.DC6' % name)
    ndir, nf = struct.unpack_from('<ii', data, 16)
    ptrs = struct.unpack_from('<%dI' % (ndir * nf), data, 24)
    # metrics table: 'Woo!' + version, then 14-byte records
    t = m.read('data\\local\\font\\latin\\%s.tbl' % name)
    nrec = (len(t) - 12) // 14
    widths = {}
    heights = {}
    for i in range(nrec):
        off = 12 + i * 14
        # u16 code, u8 pad, u8 width, u8 height, ...
        code, = struct.unpack_from('<H', t, off)
        widths[code] = t[off + 3]
        heights[code] = t[off + 4]
    pal = m.read('data\\global\\palette\\ACT1\\pal.dat')
    lum = [0.299 * pal[i * 3 + 2] + 0.587 * pal[i * 3 + 1] + 0.114 * pal[i * 3]
           for i in range(256)]

    cell_w = max(struct.unpack_from('<iii', data, p)[1] for p in ptrs)
    cell_h = max(struct.unpack_from('<iii', data, p)[2] for p in ptrs)
    glyphs = []
    peak = 1.0
    for i, p in enumerate(ptrs):
        flip, w, h = struct.unpack_from('<iii', data, p)[:3]
        length, = struct.unpack_from('<i', data, p + 28)
        px = data[p + 32:p + 32 + length]
        img = bytearray(w * h)
        x, y = 0, (0 if flip else h - 1)
        j = 0
        while j < len(px):
            b = px[j]; j += 1
            if b == 0x80:
                x = 0
                y += 1 if flip else -1
            elif b & 0x80:
                x += b & 0x7F
            else:
                img[y * w + x:y * w + x + b] = px[j:j + b]
                j += b
                x += b
        glyphs.append((w, h, img))
        for v in img:
            if v:
                peak = max(peak, lum[v])
    atlas = Image.new('RGBA', (16 * cell_w, 16 * cell_h), (0, 0, 0, 0))
    ink_top, ink_bottom = cell_h, 0
    for i, (w, h, img) in enumerate(glyphs):
        gl = Image.new('RGBA', (w, h))
        gl.putdata([(255, 255, 255, int(round(255 * lum[v] / peak))) if v
                    else (0, 0, 0, 0) for v in img])
        atlas.paste(gl, ((i % 16) * cell_w, (i // 16) * cell_h))
        # ink rows of capitals and digits: what "vertically centred" means
        if 65 <= i <= 90 or 48 <= i <= 57:
            for yy in range(h):
                if any(img[yy * w:(yy + 1) * w]):
                    ink_top = min(ink_top, yy)
                    ink_bottom = max(ink_bottom, yy + 1)
    outdir = os.path.join(config.ASSETS, 'ui')
    atlas.save(os.path.join(outdir, '%s_atlas.png' % name))
    meta = {'cell': [cell_w, cell_h],
            'widths': {str(c): widths.get(c, cell_w) for c in range(256)},
            'ascent': cell_h - 2,
            'ink': [ink_top, ink_bottom]}
    with open(os.path.join(outdir, '%s_atlas.json' % name), 'w') as f:
        json.dump(meta, f)
    print('%s: cell %dx%d, %d glyph widths, ink rows %d-%d' % (
        name, cell_w, cell_h, len(widths), ink_top, ink_bottom))


# the fonts the game draws with: font16 for tooltips and labels, font8 for
# the panels' captions and small numbers, fontformal10 / fontexocet10 and the
# large faces for the menus and area titles
FONTS = ['font16', 'font8', 'fontformal10', 'fontexocet10', 'font24', 'font30',
         'font42']


def export_fonts():
    for n in FONTS:
        export_font(n)


def export_statdisplay():
    strings = tbllib.load(mpqs())

    def resolve(key):
        v = strings.get(key, '')
        if v.strip() == '':
            return key
        return v

    props = {}
    for r in read_table('Properties.txt'):
        code = r.get('code', '')
        if not code:
            continue
        stats = []
        for i in range(1, 8):
            st = r.get('stat%d' % i, '')
            fn = r.get('func%d' % i, '')
            if not st and not fn:
                continue
            stats.append({'stat': st, 'func': fn})
        props[code] = stats

    statdesc = {}
    for r in read_table('ItemStatCost.txt'):
        stat = r.get('Stat', '')
        if not stat or r.get('descfunc', '') == '':
            continue
        statdesc[stat] = {
            'pri': r.get('descpriority', '0'),
            'func': r.get('descfunc', ''),
            'val': r.get('descval', '1'),
            'pos': resolve(r.get('descstrpos', '')),
            'neg': resolve(r.get('descstrneg', '')),
            'str2': resolve(r.get('descstr2', '')),
        }

    out = os.path.join(config.ASSETS, 'items')
    with open(os.path.join(out, 'props_display.json'), 'w') as f:
        json.dump(props, f, separators=(',', ':'))
    with open(os.path.join(out, 'statdesc.json'), 'w') as f:
        json.dump(statdesc, f, separators=(',', ':'))
    print('props_display: %d, statdesc: %d' % (len(props), len(statdesc)))
    for k in ['strength', 'maxhp', 'item_armor_percent', 'fireresist']:
        if k in statdesc:
            print(' ', k, statdesc[k])


if __name__ == '__main__':
    export_fonts()
    export_statdisplay()
