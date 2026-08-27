"""Export Act 1 monster spritesheets (all animation modes, COF-composited)."""
import os
import config
import sprites
from sprites import mpqs, composite_sheet, save

# token -> friendly name (from monstats Code column)
ROSTER = {
    'FA': 'fallen', 'FS': 'fallen_shaman', 'ZM': 'zombie', 'SK': 'skeleton',
    'CR': 'corrupt_rogue', 'BK': 'foul_crow', 'YE': 'brute', 'WR': 'wraith',
    'BH': 'afflicted', 'SI': 'quill_rat', 'GZ': 'griswold', '5P': 'smith',
    'AN': 'andariel', 'VK': 'valkyrie', 'DV': 'vulture',
    'BN': 'crow_nest', 'EC': 'hell_bovine', 'FE': 'fetish',
    'SP': 'spider', 'VA': 'vampire', 'GM': 'goatman',
}
SKIP_EXISTING = True
PREFERRED = ['LIT', 'HVY', 'MED']


def token_files(token):
    """(comp, mode, wclass) -> {armor: exists}. Also collect COF list."""
    idx = {}
    cofs = []
    for path in mpqs().list():
        p = path.split('\\')
        if len(p) < 6 or p[2].lower() != 'monsters' or p[3].upper() != token.upper():
            continue
        fn = p[-1]
        if p[4].upper() == 'COF':
            cofs.append(fn[:fn.rfind('.')].upper())
            continue
        if fn[-4:].lower() not in ('.dcc', '.dc6'):
            continue
        stem = fn[:-4].upper()
        if len(stem) < 11:
            continue
        comp, armor, md, wc = stem[2:4], stem[4:7], stem[7:9], stem[9:]
        idx.setdefault((comp, md, wc), set()).add(armor)
    return idx, cofs


def build():
    outdir = os.path.join(config.ASSETS, 'monsters')
    total = fails = 0
    for token, name in ROSTER.items():
        if SKIP_EXISTING and os.path.isdir(os.path.join(outdir, name)):
            continue
        idx, cofs = token_files(token)
        for stem in cofs:
            mode, wclass = stem[2:4], stem[4:]
            # pick a variant per comp appearing for this mode+wclass
            gear = {}
            for (comp, md, wc), armors in idx.items():
                if md == mode and wc == wclass:
                    gear[comp] = next((a for a in PREFERRED if a in armors),
                                      sorted(armors)[0])
            if not gear:
                continue
            try:
                sheet, meta = composite_sheet('monsters', token, mode, wclass, gear)
                out = os.path.join(outdir, name,
                                   '%s_%s_%s.png' % (name, mode.lower(), wclass.lower()))
                save(sheet, meta, out)
                total += 1
            except Exception as e:
                fails += 1
                print('  FAIL %s %s%s: %s' % (token, mode, wclass, e))
        print('%s (%s): done' % (name, token))
    print('monsters: %d sheets, %d failed' % (total, fails))


if __name__ == '__main__':
    build()
