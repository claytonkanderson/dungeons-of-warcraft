"""Export missile + overlay sprites used by the Amazon skill set."""
import os
import json
import config
import sprites
from sprites import mpqs, simple_sheet, save

# CelFile values (from missiles.txt) needed by the Amazon skills we ship,
# plus generic arrow art. Names are matched case-insensitively against
# data\global\missiles\*.dcc.
WANTED = [
    'arrow', 'arrowinground', 'arrowbreaking',
    'firearrow', 'firearrowexplode', 'firearrowexplode2', 'firearrowexplode3',
    'icearrow', 'icearrowexplode',
    'exparrowexplode', 'explodingarrowdebris01', 'explodingarrowdebris02',
    'explodingarrowdebris03',
    'safearrow',                     # magic arrow
    'javelin', 'javelininground',
    'lightningbolt', 'lightning', 'chargedbolt',
    'plaguejavelin', 'plaguejavelinexplosioncloud', 'poisoncloud',
    'poisonjavelin', 'poisonjavtrail',
    'iceboltexplode', 'frozenorbnova',   # freezing arrow burst reuse
    'missileexplosionfire', 'firenova',
    # monster missiles
    'spikefiendmissle', 'shamanfireball', 'shamanfireballexplodefinal',
    'inferno', 'diablomissile',
    'poisonnova', 'andarielspell',      # Andariel's poison spray
]


def build():
    m = mpqs()
    byname = {}
    for path in m.list():
        p = path.split('\\')
        if len(p) >= 4 and p[2].lower() == 'missiles':
            byname[p[-1][:p[-1].rfind('.')].lower()] = path
    outdir = os.path.join(config.ASSETS, 'missiles')
    manifest = {}
    done = 0
    for want in WANTED:
        path = byname.get(want.lower())
        if path is None:
            print('  missing missile art:', want)
            continue
        try:
            sheet, meta = simple_sheet(path)
            out = os.path.join(outdir, want.lower() + '.png')
            save(sheet, meta, out)
            manifest[want.lower()] = meta
            done += 1
        except Exception as e:
            print('  FAIL %s: %s' % (want, e))
    with open(os.path.join(outdir, 'manifest.json'), 'w') as f:
        json.dump(manifest, f)
    print('missiles: %d sheets' % done)


if __name__ == '__main__':
    build()
