"""Parse D2 excel .txt tables into assets/gamedata.json."""
import os
import json
import config
from sprites import mpqs


def read_table(name):
    """Tab-separated excel table -> list of row dicts (strings, '' for empty)."""
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


def build():
    out = {}

    # --- Amazon skills + generic Attack/Throw ------------------------------
    skills = read_table('skills.txt')
    keep = [r for r in skills if r.get('charclass') == 'ama'
            or r.get('skill') in ('Attack', 'Throw')]
    out['skills'] = {r['skill']: r for r in keep}
    # id -> name for every skill (chance-to-cast display etc.)
    out['skill_names'] = {r['Id']: r['skill'] for r in skills
                          if r.get('Id') and r.get('skill')}

    skilldesc = read_table('skilldesc.txt')
    out['skilldesc'] = {r['skilldesc']: {
        'page': r.get('SkillPage', ''), 'row': r.get('SkillRow', ''),
        'col': r.get('SkillColumn', ''), 'icon': r.get('IconCel', ''),
        'strname': r.get('str name', ''),
    } for r in skilldesc if r.get('skilldesc')}

    # --- Missiles: keep every row; game indexes by name --------------------
    missiles = read_table('Missiles.txt')
    mcols = ['Missile', 'Vel', 'MaxVel', 'Accel', 'Range', 'LevRange',
             'CelFile', 'LoopAnim', 'animrate', 'AnimLen', 'AnimSpeed',
             'CollideKill', 'ExplosionMissile', 'SubMissile1', 'SubMissile2',
             'SubMissile3', 'HitSubMissile1', 'CltHitSubMissile1', 'Trans',
             'LightRadius', 'Red', 'Green', 'Blue']
    out['missiles'] = {r['Missile']: {c: r.get(c, '') for c in mcols}
                       for r in missiles if r.get('Missile')}

    # --- Act 1 monsters ----------------------------------------------------
    monstats = read_table('monstats.txt')
    out['monstats'] = {}
    for r in monstats:
        if not r.get('Id'):
            continue
        out['monstats'][r['Id']] = {
            'code': r.get('Code', ''), 'name': r.get('NameStr', ''),
            'level': r.get('Level', ''), 'MonSound': r.get('MonSound', ''),
            'minHP': r.get('minHP', ''), 'maxHP': r.get('maxHP', ''),
            'AC': r.get('AC', ''), 'Exp': r.get('Exp', ''),
            'A1MinD': r.get('A1MinD', ''), 'A1MaxD': r.get('A1MaxD', ''),
            'A1TH': r.get('A1TH', ''), 'A2MinD': r.get('A2MinD', ''),
            'A2MaxD': r.get('A2MaxD', ''), 'A2TH': r.get('A2TH', ''),
            'Velocity': r.get('Velocity', ''), 'Run': r.get('Run', ''),
            'TC': r.get('TreasureClass1', ''),
            'MissA1': r.get('MissA1', ''), 'MissA2': r.get('MissA2', ''),
            'BaseW': r.get('BaseW', ''),
            'comps': {c: r.get(c, '') for c in
                      ('HD', 'TR', 'LG', 'RA', 'LA', 'RH', 'LH', 'SH',
                       'S1', 'S2', 'S3', 'S4', 'S5', 'S6', 'S7', 'S8')},
        }

    # --- Char stats + experience ------------------------------------------
    charstats = read_table('CharStats.txt')
    ama = next((r for r in charstats if r.get('class', '').lower() == 'amazon'), None)
    out['charstats'] = ama or {}

    exp = read_table('experience.txt')
    out['experience'] = [r.get('Amazon', '') for r in exp if r.get('Amazon')]

    os.makedirs(config.ASSETS, exist_ok=True)
    path = os.path.join(config.ASSETS, 'gamedata.json')
    with open(path, 'w') as f:
        json.dump(out, f)
    print('gamedata.json: %d skills, %d missiles, %d monsters'
          % (len(out['skills']), len(out['missiles']), len(out['monstats'])))
    return out


if __name__ == '__main__':
    build()
