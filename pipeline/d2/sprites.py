"""Shared sprite compositing for the pipeline.

Builds spritesheets (rows = directions, cols = frames) from COF-composited
DCC/DC6 layers, and emits the metadata the game needs: cell size, origin
(the D2 unit origin — feet — within a cell), frame counts, per-frame COF
trigger flags, and animation rate from animdata.d2.
"""
import os
import json
import struct
import config
from mpq import MPQSet
from cof import COF
import dcc as dcclib
import dc6 as dc6lib
from PIL import Image

_mpq = None
_pal = {}
_animdata = None


def mpqs():
    global _mpq
    if _mpq is None:
        _mpq = MPQSet([os.path.join(config.D2_DIR, a) for a in config.ARCHIVES])
    return _mpq


def palette(act='act1'):
    if act not in _pal:
        raw = mpqs().read('data\\global\\palette\\%s\\pal.dat' % act)
        flat = []
        for i in range(256):
            flat += [raw[i * 3 + 2], raw[i * 3 + 1], raw[i * 3]]
        _pal[act] = flat
    return _pal[act]


def animdata():
    """cofname (e.g. 'AMWLBOW') -> (frames_per_dir, speed, flags[144])."""
    global _animdata
    if _animdata is None:
        raw = mpqs().read('data\\global\\animdata.d2')
        _animdata = {}
        pos = 0
        for _ in range(256):
            count, = struct.unpack_from('<I', raw, pos)
            pos += 4
            for _ in range(count):
                name = raw[pos:pos + 8].split(b'\x00')[0].decode('latin-1').upper()
                fpd, speed = struct.unpack_from('<II', raw, pos + 8)
                flags = list(raw[pos + 16:pos + 16 + 144])
                _animdata[name] = (fpd, speed, flags)
                pos += 16 + 144
    return _animdata


def decode_sprite(path):
    data = mpqs().read(path)
    if path.lower().endswith('.dc6'):
        return dc6lib.decode(data)
    return dcclib.decode(data)


def paste_frame(sheet, flat_pal, d, fi, cx, cy):
    im = Image.frombytes('P', (d['width'], d['height']), d['frames'][fi])
    im.putpalette(flat_pal)
    im.info['transparency'] = 0
    sheet.alpha_composite(im.convert('RGBA'), (cx, cy))


def composite_sheet(kind, token, mode, wclass, layer_variants, act='act1'):
    """Composite one animation into (PIL sheet, metadata dict).

    layer_variants: dict comp -> armor code (e.g. {'TR':'LIT', 'LH':'AM1'}).
    Layers in the COF but absent from layer_variants (or with no file) are
    skipped. Cell origin metadata lets the game anchor feet at y=0.
    """
    m = mpqs()
    base = 'data\\global\\%s\\%s' % (kind, token)
    c = COF(m.read('%s\\COF\\%s%s%s.cof' % (base, token, mode, wclass)))
    layers = {}
    used = {}
    for lay in c.layers:
        comp = lay['comp']
        armor = layer_variants.get(comp)
        if armor is None:
            continue
        wc = (lay['wclass'] or wclass).upper()
        path = '%s\\%s\\%s%s%s%s%s' % (base, comp, token, comp, armor, mode, wc)
        for ext in ('.dcc', '.DC6'):
            try:
                layers[lay['comp_idx']] = decode_sprite(path + ext)
                used[comp] = armor
                break
            except FileNotFoundError:
                continue
    if not layers:
        raise FileNotFoundError('no layers for %s %s %s' % (token, mode, wclass))

    ndirs = max(len(v) for v in layers.values())
    xmin = min(d['xmin'] for v in layers.values() for d in v)
    ymin = min(d['ymin'] for v in layers.values() for d in v)
    xmax = max(d['xmin'] + d['width'] for v in layers.values() for d in v)
    ymax = max(d['ymin'] + d['height'] for v in layers.values() for d in v)
    w, h = xmax - xmin, ymax - ymin
    flat_pal = palette(act)
    sheet = Image.new('RGBA', (w * c.nframes, h * ndirs), (0, 0, 0, 0))
    for di in range(ndirs):
        order = c.priority[di % c.ndirs]
        for fi in range(c.nframes):
            for comp_idx in order[fi]:
                v = layers.get(comp_idx)
                if v is None:
                    continue
                d = v[di % len(v)]
                if fi < len(d['frames']):
                    paste_frame(sheet, flat_pal, d, fi,
                                fi * w + d['xmin'] - xmin, di * h + d['ymin'] - ymin)

    cofname = ('%s%s%s' % (token, mode, wclass)).upper()
    ad = animdata().get(cofname)
    fps = 25.0 * ad[1] / 256.0 if ad else 25.0
    triggers = [i for i in range(c.nframes) if ad and ad[2][i]] if ad else \
               [i for i, k in enumerate(c.keyframes) if k]
    meta = {
        'token': token, 'mode': mode, 'wclass': wclass,
        'cell': [w, h], 'origin': [-xmin, -ymin],   # D2 (0,0) within a cell
        'dirs': ndirs, 'frames': c.nframes, 'fps': round(fps, 3),
        'triggers': triggers,                        # action/event frames
        'layers': used,
    }
    return sheet, meta


def simple_sheet(path, act='act1'):
    """Sheet + metadata for a plain (layerless) DCC/DC6, e.g. missiles."""
    dirs = decode_sprite(path)
    ndirs = len(dirs)
    nframes = max(len(d['frames']) for d in dirs)
    xmin = min(d['xmin'] for d in dirs)
    ymin = min(d['ymin'] for d in dirs)
    xmax = max(d['xmin'] + d['width'] for d in dirs)
    ymax = max(d['ymin'] + d['height'] for d in dirs)
    w, h = xmax - xmin, ymax - ymin
    flat_pal = palette(act)
    sheet = Image.new('RGBA', (w * nframes, h * ndirs), (0, 0, 0, 0))
    for di, d in enumerate(dirs):
        for fi in range(len(d['frames'])):
            paste_frame(sheet, flat_pal, d, fi,
                        fi * w + d['xmin'] - xmin, di * h + d['ymin'] - ymin)
    meta = {'cell': [w, h], 'origin': [-xmin, -ymin],
            'dirs': ndirs, 'frames': nframes}
    return sheet, meta


def save(sheet, meta, out_png):
    os.makedirs(os.path.dirname(out_png), exist_ok=True)
    sheet.save(out_png)
    with open(out_png[:-4] + '.json', 'w') as f:
        json.dump(meta, f)
