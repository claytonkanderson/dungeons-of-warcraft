"""Export item quality data -> assets/items/.

  uniques.json    unique items (UniqueItems.txt) with up to 12 props
  setitems.json   set items (SetItems.txt + Sets.txt for set names)
  affixes.json    magic prefixes/suffixes with itype/etype filters + mods
  rarenames.json  rare name fragments (RarePrefix/RareSuffix)
  itemtypes.json  item type hierarchy (ItemTypes.txt) for itype matching

All names are resolved through the .tbl string tables when a matching key
exists; otherwise the verbatim txt value is kept. Keys that resolve to a
single space (patchstring blanking quirk) count as unresolved.
"""
import os
import json
import config
import tbl
from sprites import mpqs


def read_table(name):
    """Tab-separated excel table -> list of row dicts (strings, '' for empty).
    (Same idiom as export_items.read_table; existing files stay untouched.)"""
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


def g(r, *names):
    """Row value under any of several column spellings (case-insensitive)."""
    for n in names:
        if n in r:
            return r[n]
    lower = {k.lower(): v for k, v in r.items()}
    for n in names:
        if n.lower() in lower:
            return lower[n.lower()]
    return ''


class Resolver:
    """strings.get with fallback counting; ' ' values count as unresolved."""

    def __init__(self, strings):
        self.strings = strings
        self.fallbacks = 0

    def __call__(self, key):
        key = key.strip()
        if not key:
            return key
        val = self.strings.get(key)
        if val is None or val == ' ':
            self.fallbacks += 1
            return key
        return val


def props(r, count, fmt=('prop%d', 'par%d', 'min%d', 'max%d')):
    """propN/parN/minN/maxN (or modN* via fmt) -> list, skipping empty codes."""
    cfmt, pfmt, nfmt, xfmt = fmt
    out = []
    for i in range(1, count + 1):
        code = g(r, cfmt % i).strip()
        if not code:
            continue
        out.append({'code': code, 'param': g(r, pfmt % i),
                    'min': g(r, nfmt % i), 'max': g(r, xfmt % i)})
    return out


def collect(r, prefix, count):
    """itype1..N / etype1..N -> list of non-empty values."""
    out = []
    for i in range(1, count + 1):
        v = g(r, '%s%d' % (prefix, i)).strip()
        if v:
            out.append(v)
    return out


def dump(obj, outdir, fname):
    with open(os.path.join(outdir, fname), 'w') as f:
        json.dump(obj, f, separators=(',', ':'))


def build_uniques(res):
    out = []
    for r in read_table('UniqueItems.txt'):
        code = g(r, 'code').strip()
        if not code:
            continue
        out.append({'name': res(g(r, 'index')),
                    'code': code,
                    'lvl': g(r, 'lvl', 'level'),
                    'lvlreq': g(r, 'lvl req', 'levelreq'),
                    'rarity': g(r, 'rarity') or '1',
                    'enabled': g(r, 'enabled') == '1',
                    'props': props(r, 12)})
    return out


def build_setitems(res):
    # Sets.txt: set id ('index') -> display name ('name', tbl-resolved).
    setnames = {}
    for r in read_table('Sets.txt'):
        sid = g(r, 'index').strip()
        if sid:
            setnames[sid] = res(g(r, 'name') or sid)
    out = []
    for r in read_table('SetItems.txt'):
        name = g(r, 'index').strip()
        code = g(r, 'item').strip()
        if not name and not code:
            continue
        sid = g(r, 'set').strip()
        out.append({'name': res(name),
                    'set': setnames.get(sid) or res(sid),
                    'code': code,
                    'lvl': g(r, 'lvl', 'level'),
                    'lvlreq': g(r, 'lvl req', 'levelreq'),
                    'rarity': g(r, 'rarity') or '1',
                    'props': props(r, 9)})
    return out


def build_affixes(res, src):
    out = []
    for r in read_table(src):
        name = g(r, 'Name', 'name').strip()
        if not name or g(r, 'spawnable') != '1':
            continue
        out.append({'name': res(name),
                    'lvl': g(r, 'level'),
                    'maxlevel': g(r, 'maxlevel'),
                    'levelreq': g(r, 'levelreq'),
                    'frequency': g(r, 'frequency') or '0',
                    'group': g(r, 'group'),
                    'classspecific': g(r, 'classspecific'),
                    'class': g(r, 'class'),
                    'rare': g(r, 'rare') == '1',
                    'spawnable': True,
                    'itypes': collect(r, 'itype', 7),
                    'etypes': collect(r, 'etype', 5),
                    'props': props(r, 3, ('mod%dcode', 'mod%dparam',
                                          'mod%dmin', 'mod%dmax'))})
    return out


def build_rarenames(res, src):
    out = []
    for r in read_table(src):
        name = g(r, 'name', 'Name').strip()
        if name:
            out.append(res(name))
    return out


def build_itemtypes():
    out = {}
    for r in read_table('ItemTypes.txt'):
        code = g(r, 'Code').strip()
        if not code:
            continue
        out[code] = {'name': g(r, 'ItemType'),
                     'equiv1': g(r, 'Equiv1').strip(),
                     'equiv2': g(r, 'Equiv2').strip()}
    return out


def build():
    strings = tbl.load(mpqs())
    print('strings: %d entries' % len(strings))
    outdir = os.path.join(config.ASSETS, 'items')
    os.makedirs(outdir, exist_ok=True)

    res = Resolver(strings)
    uniques = build_uniques(res)
    dump(uniques, outdir, 'uniques.json')
    print('uniques.json: %d uniques (%d name fallbacks)'
          % (len(uniques), res.fallbacks))

    res = Resolver(strings)
    setitems = build_setitems(res)
    dump(setitems, outdir, 'setitems.json')
    print('setitems.json: %d set items (%d name fallbacks)'
          % (len(setitems), res.fallbacks))

    res = Resolver(strings)
    affixes = {'prefixes': build_affixes(res, 'MagicPrefix.txt'),
               'suffixes': build_affixes(res, 'MagicSuffix.txt')}
    dump(affixes, outdir, 'affixes.json')
    print('affixes.json: %d prefixes, %d suffixes (%d name fallbacks)'
          % (len(affixes['prefixes']), len(affixes['suffixes']), res.fallbacks))

    res = Resolver(strings)
    rarenames = {'prefixes': build_rarenames(res, 'RarePrefix.txt'),
                 'suffixes': build_rarenames(res, 'RareSuffix.txt')}
    dump(rarenames, outdir, 'rarenames.json')
    print('rarenames.json: %d prefixes, %d suffixes (%d name fallbacks)'
          % (len(rarenames['prefixes']), len(rarenames['suffixes']),
             res.fallbacks))

    itemtypes = build_itemtypes()
    dump(itemtypes, outdir, 'itemtypes.json')
    print('itemtypes.json: %d types' % len(itemtypes))

    print('examples: uniques %s' % ['%s (%s)' % (u['name'], u['code'])
                                    for u in uniques[:5]])
    print('examples: affixes %s'
          % ['%s -> %s' % (a['name'], [p['code'] for p in a['props']])
             for a in affixes['prefixes'][:3] + affixes['suffixes'][:2]])


if __name__ == '__main__':
    build()
