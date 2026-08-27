"""Export Amazon spritesheets: every animation mode x weapon class we use."""
import os
import config
import sprites
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


def variants_for(mode, wclass):
    """Resolve GEAR against what actually exists for this mode+wclass."""
    m = mpqs()
    resolved = {}
    for comp, primary in GEAR.items():
        for armor in [primary] + FALLBACK.get(comp, []):
            found = False
            for wc in (wclass,):
                base = 'data\\global\\CHARS\\%s\\%s\\%s%s%s%s%s' % (
                    TOKEN, comp, TOKEN, comp, armor, mode, wc)
                if m.has(base + '.dcc') or m.has(base + '.DC6'):
                    resolved[comp] = armor
                    found = True
                    break
            if found:
                break
    return resolved


def build():
    outdir = os.path.join(config.ASSETS, 'amazon')
    done = err = 0
    for mode, wclass, cofpath in list_cofs():
        try:
            gear = variants_for(mode, wclass)
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
