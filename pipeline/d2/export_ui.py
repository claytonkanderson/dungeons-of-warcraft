"""Export UI art: Amazon skill icons, HUD pieces, original D2 panels."""
import os
import struct
import config
import sprites
from sprites import mpqs, palette, simple_sheet, save
from PIL import Image


def _dc6_frames(name):
    """Raw DC6 frames as RGBA images (UI art: no per-frame offsets used)."""
    data = mpqs().read(name)
    ndir, nf = struct.unpack_from('<ii', data, 16)
    ptrs = struct.unpack_from('<%dI' % (ndir * nf), data, 24)
    flat = palette('act1')
    out = []
    for p in ptrs:
        flip, w, h = struct.unpack_from('<iii', data, p)[:3]
        length, = struct.unpack_from('<i', data, p + 28)
        px = data[p + 32:p + 32 + length]
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
                img[y * w + x:y * w + x + b] = px[i:i + b]
                i += b
                x += b
        im = Image.frombytes('P', (w, h), bytes(img))
        im.putpalette(flat)
        im.info['transparency'] = 0
        out.append(im.convert('RGBA'))
    return out


def composite_pages(name, out_base):
    """320x432 D2 panel pages: frames grouped in fours (256+64 x 256+176)."""
    frames = _dc6_frames(name)
    pages = []
    for g in range(0, len(frames), 4):
        page = Image.new('RGBA', (320, 432), (0, 0, 0, 0))
        page.paste(frames[g + 0], (0, 0))
        page.paste(frames[g + 1], (256, 0))
        page.paste(frames[g + 2], (0, 256))
        page.paste(frames[g + 3], (256, 256))
        pages.append(page)
    outdir = os.path.join(config.ASSETS, 'ui')
    os.makedirs(outdir, exist_ok=True)
    for i, page in enumerate(pages):
        page.save(os.path.join(outdir, '%s_%d.png' % (out_base, i)))
    print('%s: %d pages' % (out_base, len(pages)))


def composite_strip(name, out_base, limit=None):
    """Left-to-right bottom-aligned strip (the control panel)."""
    frames = _dc6_frames(name)
    if limit:
        frames = frames[:limit]
    w = sum(f.width for f in frames)
    h = max(f.height for f in frames)
    strip = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    x = 0
    for f in frames:
        strip.paste(f, (x, h - f.height))
        x += f.width
    outdir = os.path.join(config.ASSETS, 'ui')
    os.makedirs(outdir, exist_ok=True)
    strip.save(os.path.join(outdir, out_base + '.png'))
    print('%s: %dx%d from %d segments' % (out_base, w, h, len(frames)))


def export_orbs():
    frames = _dc6_frames('data\\global\\ui\\PANEL\\hlthmana.DC6')
    outdir = os.path.join(config.ASSETS, 'ui')
    for i, f in enumerate(frames):
        f.save(os.path.join(outdir, 'orb_%d.png' % i))
    print('orbs: %d frames' % len(frames))


def build():
    outdir = os.path.join(config.ASSETS, 'ui')
    # Skill icons: DC6 with 2 frames per icon (normal, pressed)
    for name, path in [
        ('amskillicon', 'data\\global\\ui\\SPELLS\\AmSkillicon.DC6'),
        ('skilliconpanel', 'data\\global\\ui\\SPELLS\\Skillicon.DC6'),
        ('viewmodel_bow', 'data\\global\\items\\invhbw.DC6'),
        # main-menu furniture: the character-select slot frame and the
        # stone button plate, both 2 frames (idle, pressed)
        ('charbox', 'data\\global\\ui\\CharSelect\\charselectbox.DC6'),
        ('charbox_off', 'data\\global\\ui\\CharSelect\\charselectboxgrey.dc6'),
        ('menubutton', 'data\\global\\ui\\FrontEnd\\WideButtonBlank.dc6'),
    ]:
        try:
            sheet, meta = simple_sheet(path)
            save(sheet, meta, os.path.join(outdir, name + '.png'))
            print('%s: %s frames cell %s' % (name, meta['frames'], meta['cell']))
        except FileNotFoundError:
            print('missing', path)
    composite_strip('data\\global\\ui\\PANEL\\800ctrlpnl7.dc6', 'ctrlpanel', limit=6)
    composite_pages('data\\global\\ui\\PANEL\\invchar6.dc6', 'invchar')
    composite_pages('data\\global\\ui\\SPELLS\\skltree_a_back.DC6', 'skltree')
    export_orbs()


if __name__ == '__main__':
    build()
