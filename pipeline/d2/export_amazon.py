"""Export Amazon spritesheets: every animation mode x weapon class we use."""
import os
import config
import sprites
from cof import COF
from sprites import mpqs, composite_sheet, save

TOKEN = 'AM'
# gear: light armor everywhere, Amazon's own bow/javelins in hand
GEAR = {'HD': 'LIT', 'TR': 'LIT', 'LG': 'LIT', 'RA': 'LIT', 'LA': 'LIT',
        'S1': 'LIT', 'S2': 'LIT',
        'RH': 'JAV', 'LH': 'AM1', 'SH': 'BUC'}
# per-layer fallbacks tried in order when the primary gear code has no file
FALLBACK = {'HD': ['BHM'], 'RH': ['AXE', 'JAV', 'SPR'], 'LH': ['AM1', 'AM2'],
            'SH': ['BUC', 'SML']}


def list_cofs():
    out = []
    for path in mpqs().list():
        p = path.split('\\')
        if len(p) >= 6 and p[2].upper() == 'CHARS' and p[3].upper() == TOKEN \
                and p[4].upper() == 'COF':
            stem = p[-1][:p[-1].rfind('.')].upper()
            out.append((stem[2:4], stem[4:], path))
    return out


def layer_wclasses(cof, wclass):
    """comp -> the weapon class its art is actually filed under.

    Each COF layer carries its own class: in the bow animation the head,
    torso, legs and shoulders are authored as '1ht' while only the arms and
    the bow itself are 'bow'. Probing every layer at the animation's own
    class finds nothing for most of them, which is how this exporter used to
    drop everything but the arms.
    """
    return {lay['comp']: (lay['wclass'] or wclass).upper() for lay in cof.layers}


def variants_for(mode, wclass, cof):
    """Resolve GEAR against what actually exists for this mode+wclass."""
    m = mpqs()
    by_comp = layer_wclasses(cof, wclass)
    resolved = {}
    for comp, primary in GEAR.items():
        wc = by_comp.get(comp)
        if wc is None:
            continue                    # this animation has no such layer
        for armor in [primary] + FALLBACK.get(comp, []):
            base = 'data\\global\\CHARS\\%s\\%s\\%s%s%s%s%s' % (
                TOKEN, comp, TOKEN, comp, armor, mode, wc)
            if m.has(base + '.dcc') or m.has(base + '.DC6'):
                resolved[comp] = armor
                break
    return resolved


def build():
    outdir = os.path.join(config.ASSETS, 'amazon')
    done = err = 0
    for mode, wclass, cofpath in list_cofs():
        try:
            gear = variants_for(mode, wclass, COF(mpqs().read(cofpath)))
            sheet, meta = composite_sheet('CHARS', TOKEN, mode, wclass, gear)
            out = os.path.join(outdir, 'am_%s_%s.png' % (mode.lower(), wclass.lower()))
            save(sheet, meta, out)
            done += 1
        except Exception as e:
            err += 1
            print('  FAIL %s%s: %s' % (mode, wclass, e))
    print('amazon: %d sheets, %d failed' % (done, err))


if __name__ == '__main__':
    build()
