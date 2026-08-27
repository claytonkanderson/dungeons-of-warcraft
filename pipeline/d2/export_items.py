"""Export item/loot data + sprites -> assets/items/.

  items.json      item stats keyed by code (weapons/armor/misc + 'gold')
  treasure.json   raw treasure classes for the drop system
  flippy/*.png    ground-drop animations (one sheet + .json sidecar each)
  inv/*.png       inventory art singles
"""
import os
import json
import config
import tbl
from sprites import mpqs, simple_sheet, save


def read_table(name):
    """Tab-separated excel table -> list of row dicts (strings, '' for empty).
    (Copied from export_tables.read_table; that file must stay untouched.)"""
    raw = mpqs().read('data\\global\\excel\\%s' % name).decode('latin-1')
    lines = [l for l in raw.replace('\r', '\n').split('\n') if l.strip()]
    cols = lines[0].split('\t')
    rows = []
    for line in lines[1:]:
        vals = line.split('\t')
        if vals and vals[0].lower() == 'expansion':
            continue
        rows.append({c: (vals[i] if i < len(vals) else '') for i, c in enumerate(cols)})
    return rows


BASE_COLS = ['type', 'invwidth', 'invheight', 'invfile', 'flippyfile',
             'level', 'levelreq', 'rarity', 'cost', 'reqstr', 'reqdex']


def build_items(strings):
    """weapons/armor/misc -> dict code -> item, with TBL-resolved names."""
    items = {}
    # Bows/2h swords keep damage in 2handmindam/2handmaxdam, throwables in
    # minmisdam/maxmisdam -- mindam/maxdam alone leaves them damageless.
    for src, extra in (('weapons.txt', ('mindam', 'maxdam',
                                        '2handmindam', '2handmaxdam',
                                        'minmisdam', 'maxmisdam')),
                       ('armor.txt', ('minac', 'maxac')),
                       ('misc.txt', ())):
        for r in read_table(src):
            code = r.get('code', '').strip()
            if not code:
                continue
            namestr = r.get('namestr', '').strip() or code
            item = {'code': code, 'name': strings.get(namestr, namestr)}
            for c in BASE_COLS + list(extra):
                item[c] = r.get(c, '')
            items[code] = item

    # 'gold' pseudo item (drops as a pile, never occupies inventory cells)
    gld = items.get('gld')
    if gld:
        items['gold'] = dict(gld, code='gold')
    else:
        items['gold'] = {'code': 'gold', 'name': strings.get('gld', 'Gold'),
                         'type': 'gold', 'invwidth': '1', 'invheight': '1',
                         'invfile': 'invgld', 'flippyfile': 'flpgld',
                         'level': '', 'levelreq': '', 'rarity': '', 'cost': ''}
    return items


def build_treasure():
    """TreasureClassEx (or classic TreasureClass) -> dict, raw strings only."""
    rows = src = None
    for name in ('TreasureClassEx.txt', 'TreasureClass.txt'):
        try:
            rows, src = read_table(name), name
            break
        except FileNotFoundError:
            continue
    out = {}
    if rows is None:
        return out, 'none'
    for r in rows:
        name = r.get('Treasure Class', '').strip()
        if not name:
            continue
        entries = []
        for i in range(1, 11):
            it = r.get('Item%d' % i, '').strip()
            if it:
                entries.append([it, r.get('Prob%d' % i, '')])
        out[name] = {'picks': r.get('Picks', ''),
                     'nodrop': r.get('NoDrop', ''),
                     'items': entries}
    return out, src


def export_sprites(names, subdir):
    """Distinct DC6 names under data\\global\\items -> sheets in assets/items/<subdir>."""
    m = mpqs()
    outdir = os.path.join(config.ASSETS, 'items', subdir)
    done = missing = failed = 0
    for name in names:
        path = None
        for ext in ('.dc6', '.DC6'):
            cand = 'data\\global\\items\\%s%s' % (name, ext)
            if m.has(cand):
                path = cand
                break
        if path is None:
            missing += 1
            continue
        try:
            sheet, meta = simple_sheet(path)
            save(sheet, meta, os.path.join(outdir, name + '.png'))
            done += 1
        except Exception as e:
            print('  FAIL %s: %s' % (name, e))
            failed += 1
    print('%s: %d sheets, %d missing from archives, %d failed'
          % (subdir, done, missing, failed))


def build():
    strings = tbl.load(mpqs())
    print('strings: %d entries from %d .tbl files'
          % (len(strings), sum(1 for t in tbl.TABLES if mpqs().has(t))))

    items = build_items(strings)
    outdir = os.path.join(config.ASSETS, 'items')
    os.makedirs(outdir, exist_ok=True)
    with open(os.path.join(outdir, 'items.json'), 'w') as f:
        json.dump(items, f)
    resolved = [it['name'] for c, it in sorted(items.items())
                if it['name'] != c and it['name'] in strings.values()]
    print('items.json: %d items, e.g. %s'
          % (len(items), ', '.join(repr(n) for n in resolved[:5])))

    treasure, src = build_treasure()
    with open(os.path.join(outdir, 'treasure.json'), 'w') as f:
        json.dump(treasure, f)
    print('treasure.json: %d classes (from %s)' % (len(treasure), src))

    flippies = sorted({it['flippyfile'].lower()
                       for it in items.values() if it.get('flippyfile')})
    invs = sorted({it['invfile'].lower()
                   for it in items.values() if it.get('invfile')})
    export_sprites(flippies, 'flippy')
    export_sprites(invs, 'inv')


if __name__ == '__main__':
    build()
