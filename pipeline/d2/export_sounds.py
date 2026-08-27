"""Export the game's SFX set from d2sfx/d2speech into assets/sounds/.

Resolution chain: monstats.MonSound -> MonSounds.txt -> Sounds.txt -> WAV.
Group leaders in Sounds.txt own the next (Group Size - 1) rows in table
order; the game picks a random member per play, so every member is exported.
"""
import os
import json
import config
from export_tables import read_table
import mpq as mpqlib

SFX_ARCHIVES = ['patch_d2.mpq', 'd2exp.mpq', 'd2sfx.mpq', 'd2speech.mpq',
                'd2xtalk.mpq', 'd2data.mpq']

# game event -> Sounds.txt key candidates (first existing wins per slot)
EVENTS = {
    'bow_fire': [('weapon_bow_1',)],
    'xbow_fire': [('weapon_xbow_1',)],
    'melee_swing': [('weapon_1hs_small_1', 'weapon_1hs_large_1')],
    'melee_swing_large': [('weapon_1hs_large_1',)],
    'punch': [('weapon_punch_1',)],
    'staff_swing': [('weapon_staff_1', 'weapon_blunt_1', 'weapon_1hs_large_1')],
    'arrow_impact': [('impact_arrow_1',)],
    'blade_impact': [('impact_blade_1', 'impact_blade_swing_1')],
    'blunt_impact': [('impact_blunt_1',)],
    'fire_impact': [('impact_fire_1', 'monster_fireball_hit', 'sorceress_fireball')],
    'poison_impact': [('impact_poison_1',)],
    'poison_cast': [('monster_poisonbolt',)],
    'pickup': [('item_pickup',)],
    'flippy': [('item_flippy',)],
    'potion_drink': [('item_potion_drink',)],
    'potion_belt': [('item_potion',)],
    'level_up': [('cursor_level_up',)],
    'button': [('cursor_button_click', 'cursor_button')],
    'player_gethit': [('amazon_hit_1',)],
    'player_death': [('amazon_death_1',)],
    'gold_drop': [('item_gold_small', 'item_gold')],
}

# MonSounds fields worth carrying into the game
MON_FIELDS = {'attack': 'Attack1', 'attack2': 'Attack2', 'weapon': 'Weapon1',
              'hit': 'HitSound', 'death': 'DeathSound', 'neutral': 'Neutral',
              'flee': 'Flee', 'taunt': 'Taunt', 'init': 'Init'}

_sfx = None


def sfx_mpqs():
    global _sfx
    if _sfx is None:
        _sfx = mpqlib.MPQSet([os.path.join(config.D2_DIR, a) for a in SFX_ARCHIVES])
    return _sfx


def build():
    outdir = os.path.join(config.ASSETS, 'sounds')
    os.makedirs(outdir, exist_ok=True)

    rows = read_table('Sounds.txt')
    rows = [r for r in rows if r.get('Sound')]
    index_of = {r['Sound']: i for i, r in enumerate(rows)}

    exported = {}   # sound key -> True once written
    volumes = {}
    missing = []

    def group(leader):
        """Group leader key -> list of member keys (table order)."""
        i = index_of.get(leader)
        if i is None:
            return []
        n = max(1, min(int(rows[i].get('Group Size') or '1'), 12))
        return [rows[j]['Sound'] for j in range(i, min(i + n, len(rows)))
                if rows[j].get('FileName')]

    def export_key(key):
        if key in exported:
            return exported[key]
        r = rows[index_of[key]]
        fn = r['FileName'].replace('/', '\\')
        data = None
        for prefix in ('data\\global\\sfx\\', 'data\\local\\sfx\\',
                       'data\\global\\music\\', ''):
            try:
                data = sfx_mpqs().read(prefix + fn)
                break
            except (FileNotFoundError, Exception) as e:
                if isinstance(e, FileNotFoundError):
                    continue
                print('  DECODE FAIL %s (%s): %s' % (key, fn, e))
                return False
        if data is None or data[:4] != b'RIFF':
            missing.append('%s (%s)' % (key, fn))
            exported[key] = False
            return False
        with open(os.path.join(outdir, key + '.wav'), 'wb') as f:
            f.write(data)
        volumes[key] = int(r.get('Volume') or '255')
        exported[key] = True
        return True

    def export_group(leader):
        keys = [k for k in group(leader) if export_key(k)]
        return keys

    # --- generic events ----------------------------------------------------
    events = {}
    for ev, slots in EVENTS.items():
        keys = []
        for candidates in slots:
            pick = next((c for c in candidates if c in index_of), None)
            if pick is None:
                print('  event %-18s no candidate found %s' % (ev, candidates))
                continue
            keys += export_group(pick)
        if keys:
            events[ev] = keys

    # --- monsters: roster codes -> monstats -> MonSounds -------------------
    from export_monsters import ROSTER
    monstats = read_table('monstats.txt')
    monsounds = {r['Id']: r for r in read_table('MonSounds.txt') if r.get('Id')}
    want_ids = set()
    for r in monstats:
        if r.get('Code', '').upper() in ROSTER and r.get('MonSound'):
            want_ids.add(r['MonSound'])

    monsters = {}
    for mid in sorted(want_ids):
        row = monsounds.get(mid)
        if row is None:
            print('  monsound %s not in MonSounds.txt' % mid)
            continue
        entry = {}
        for field, col in MON_FIELDS.items():
            leader = row.get(col, '').strip()
            if not leader or leader not in index_of:
                continue
            keys = export_group(leader)
            if keys:
                entry[field] = keys
        if entry:
            monsters[mid] = entry

    # andariel poison-spray cast + spoken taunt
    if 'andariel' in monsters:
        keys = export_group('andariel_cast_large') + export_group('andariel_cast_small')
        if keys:
            monsters['andariel']['cast'] = keys
        taunt = export_group('monster_andariel_taunt_1')
        if taunt:
            monsters['andariel']['taunt'] = taunt

    meta = {'events': events, 'monsters': monsters, 'volumes': volumes}
    with open(os.path.join(outdir, 'sounds.json'), 'w') as f:
        json.dump(meta, f, indent=1)

    n_files = sum(1 for v in exported.values() if v)
    print('sounds: %d wavs, %d events, %d monsters -> %s' % (
        n_files, len(events), len(monsters), outdir))
    if missing:
        print('missing files: %d' % len(missing))
        for m in missing[:10]:
            print('  ', m)


if __name__ == '__main__':
    build()
