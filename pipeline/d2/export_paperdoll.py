"""Export the menu paperdoll: one strip per equipment layer, not per outfit.

The main menu shows the selected character wearing what they actually have
equipped, so the outfit is only known at runtime and cannot be baked. What
*can* be baked is every layer in isolation -- each armour class of each body
part, each helm, each shield, each weapon -- plus the COF's per-frame draw
order. The game stacks them.

Only the idle (NU) animation and the one direction that faces the camera are
exported, which is what keeps this to a couple of hundred small strips.
"""
import os
import json
import config
from cof import COF
from sprites import mpqs, decode_sprite, palette, paste_frame
from PIL import Image

TOKEN = 'AM'
MODE = 'NU'
# Direction 3 is the one that squares up to the camera: the weapon reads in
# the right hand and the shield sits beside the body instead of in front of
# it, which direction 0 does not.
FACING = 3

# every armour code the Amazon has art for, per component
CODES = {
    'HD': ['LIT', 'CAP', 'SKP', 'HLM', 'FHL', 'GHM', 'CRN', 'MSK', 'BHM'],
    'TR': ['LIT', 'MED', 'HVY'],
    'LG': ['LIT', 'MED', 'HVY'],
    'RA': ['LIT', 'MED', 'HVY'],
    'LA': ['LIT', 'MED', 'HVY'],
    'S1': ['LIT', 'MED', 'HVY'],
    'S2': ['LIT', 'MED', 'HVY'],
    'SH': ['BUC', 'SML', 'KIT', 'LRG', 'BSH', 'SPK', 'TOW'],
    'LH': ['AM1', 'AM2', 'SBW', 'LBW', 'SBB', 'LBB', 'HXB', 'LXB'],
    'RH': ['AM3', 'AXE', 'BRN', 'BSD', 'BST', 'BTX', 'BWN', 'CLB', 'CLM',
           'CRS', 'CST', 'DGR', 'DIR', 'FLA', 'FLC', 'GIX', 'GLV', 'GPL',
           'GPS', 'GSD', 'HAL', 'HAX', 'HXB', 'JAV', 'LAX', 'LSD', 'LST',
           'LXB', 'MAC', 'MAU', 'OPL', 'OPS', 'PAX', 'PIK', 'PIL', 'SCM',
           'SCY', 'SPR', 'SSD', 'SST', 'TRI', 'WHM', 'WND', 'YWN'],
}


def weapon_classes():
    """Animation classes that have an idle COF, e.g. bow / 1hs / hth."""
    out = []
    for path in mpqs().list():
        p = path.split('\\')
        if len(p) >= 6 and p[2].upper() == 'CHARS' and p[3].upper() == TOKEN \
                and p[4].upper() == 'COF':
            stem = p[-1][:p[-1].rfind('.')].upper()
            if stem[2:4] == MODE:
                out.append(stem[4:])
    return sorted(set(out))


def strip(comp, armor, wclass, outdir):
    """One layer, one direction, all frames -> PNG + placement metadata."""
    base = 'data\\global\\CHARS\\%s\\%s\\%s%s%s%s%s' % (
        TOKEN, comp, TOKEN, comp, armor, MODE, wclass)
    dirs = None
    for ext in ('.dcc', '.DC6'):
        try:
            dirs = decode_sprite(base + ext)
            break
        except FileNotFoundError:
            continue
    if dirs is None:
        return None
    d = dirs[FACING % len(dirs)]
    n = len(d['frames'])
    sheet = Image.new('RGBA', (d['width'] * n, d['height']), (0, 0, 0, 0))
    flat = palette('act1')
    for fi in range(n):
        paste_frame(sheet, flat, d, fi, fi * d['width'], 0)
    sheet.save(os.path.join(outdir, '%s_%s_%s.png'
                            % (comp.lower(), armor.lower(), wclass.lower())))
    # xmin/ymin place the layer against the D2 unit origin, which is how the
    # layers line up with each other once stacked
    return {'cell': [d['width'], d['height']],
            'off': [d['xmin'], d['ymin']], 'frames': n}


def build():
    outdir = os.path.join(config.ASSETS, 'amazon', 'paperdoll')
    os.makedirs(outdir, exist_ok=True)
    m = mpqs()
    strips = {}
    classes = {}
    for wclass in weapon_classes():
        c = COF(m.read('data\\global\\CHARS\\%s\\COF\\%s%s%s.cof'
                       % (TOKEN, TOKEN, MODE, wclass)))
        by_comp = {lay['comp']: (lay['wclass'] or wclass).upper()
                   for lay in c.layers}
        idx_to_comp = {lay['comp_idx']: lay['comp'] for lay in c.layers}
        x0 = y0 = 10 ** 6
        x1 = y1 = -10 ** 6
        present = {}
        for comp, lwc in sorted(by_comp.items()):
            for armor in CODES.get(comp, []):
                key = '%s_%s_%s' % (comp.lower(), armor.lower(), lwc.lower())
                if key not in strips:
                    meta = strip(comp, armor, lwc, outdir)
                    if meta is None:
                        continue
                    strips[key] = meta
                meta = strips[key]
                present.setdefault(comp, []).append(armor)
                x0 = min(x0, meta['off'][0])
                y0 = min(y0, meta['off'][1])
                x1 = max(x1, meta['off'][0] + meta['cell'][0])
                y1 = max(y1, meta['off'][1] + meta['cell'][1])
        if not present:
            continue
        # draw order changes per frame (an arm passes in front of the torso
        # and back again), so keep the COF's own per-frame ordering
        order = []
        for frame in c.priority[FACING % c.ndirs]:
            order.append([idx_to_comp[i] for i in frame if i in idx_to_comp])
        classes[wclass.lower()] = {
            'canvas': [x1 - x0, y1 - y0],
            'origin': [-x0, -y0],
            'frames': c.nframes,
            'weapon_comp': 'LH' if 'LH' in by_comp else (
                'RH' if 'RH' in by_comp else ''),
            'layers': {k: v.lower() for k, v in by_comp.items()},
            'codes': {k: v for k, v in present.items()},
            'order': order,
        }

    from sprites import animdata
    fps = 12.5
    ad = animdata().get('%s%sHTH' % (TOKEN, MODE))
    if ad:
        fps = round(25.0 * ad[1] / 256.0, 3)
    manifest = {'mode': MODE, 'dir': FACING, 'fps': fps,
                'classes': classes, 'strips': strips}
    with open(os.path.join(outdir, 'paperdoll.json'), 'w') as f:
        json.dump(manifest, f)
    print('paperdoll: %d layer strips, %d weapon classes (%s)'
          % (len(strips), len(classes), ' '.join(sorted(classes))))


if __name__ == '__main__':
    build()
