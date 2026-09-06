"""Export every creature spawned in a dungeon with the gameplay animation
set, plus D2-shaped combat stats derived from AzerothCore data.

Dungeon-agnostic: the roster derives from the map's actual spawn list,
bosses are matched by name from dungeon_config, and XP is normalized so a
full clear carries the character from ~(target_level-4) to target_level.

Model/texture/attachment resolution is the warcraft-art recipe:
creature_template_model -> display -> model fdid (+ scale); humanoids get
baked NPC textures, hair geosets, and their helm-slot items; equipment
becomes rigid hand attachments. Weapon/helm skins that need the (missing)
texturefiledata.db2 fall back to the nearest BLP in the model's fdid
neighborhood.
"""
import argparse
import json
import re
import struct

from config import OUT, AC, ASSETS
from casc import Storage, CascError
from db2 import WDC5
from m2 import M2Model, Skin
from blp import blp_to_png
import gltf_export
from dungeon_common import load_spawns, sql_columns
from dungeon_config import DUNGEONS

DEFIAS_HELM_DISPLAY = 15308
DEFIAS_HELM_RED_TEX = 138220

# gameplay animation sequences: stand, death, locomotion, wounds,
# melee attacks, spell casts
GAME_SEQS = {0, 1, 4, 5, 9, 10, 16, 17, 18, 19, 31, 32, 51}

# --- D2 stat mapping tuning -------------------------------------------------
# M2 model name -> voice family in build_audio.CREATURE_SFX. Every family
# listed has readable files in the local client (probed); models with no
# usable set map to "" and rely on the generic swing/impact foley.
VOICE_BY_MODEL = {
    "Worgen": "worgen", "Wolf": "wolf", "DireWolf": "wolf", "Wolf_ghost": "wolf",
    "FelBat": "bat", "Horse": "horse", "Rat": "rat", "Satyr": "satyr",
    "Raptor": "raptor", "snake": "snake", "Serpent": "snake",
    "Lasher": "lasher", "BogBeast": "bogbeast", "SeaTurtle": "seaturtle",
    "FaerieDragon": "faeriedragon", "ThunderLizard": "thunderlizard",
    "Frog": "frog", "Infernal": "infernal", "Skeleton": "skeleton",
    "Murloc": "murloc", "GoblinMale": "goblin", "Ogre": "ogre",
    "OrcMale": "orc", "NightElfMale": "nightelf", "TaurenMale": "tauren",
    # the peasant greeting set never streamed; the human combat set does
    "HumanMalePeasant": "human", "HumanMale": "human", "HumanThief": "human",
    "HumanFemale": "human_female", "GoblinShredder": "shredder",
    # the next six dungeons (pipeline/probe_voices.py found these sets)
    "QuillBoar": "quillboar", "QuillBoarCaster": "quillboar",
    "QuillBoarWarrior": "quillboar", "Crab": "crab", "Hydra": "hydra",
    "Lobstrok": "lobstrok", "NagaMale": "naga", "Siren": "siren",
    "Threshadon": "threshadon", "DwarfMale": "dwarf", "OgreMage": "ogremage",
    "OrcMaleWarriorLight": "orc", "Troglodyte": "troglodyte",
    "WaterElemental": "waterelemental", "Ghost": "ghost", "Lich": "lich",
    "Hyena": "hyena", "Shade": "shade", "GnomeBot": "mechanical",
    "GnomeAlertBot": "mechanical", "GnomePounder": "mechanical",
    "GnomeSpiderTank": "mechanical", "GnomeMechaStrider": "mechanical",
}



def sql_rows(path, pattern):
    import re
    pat = re.compile(pattern)
    for line in path.read_text(encoding="utf-8").splitlines():
        m = pat.match(line)
        if m:
            yield m, line


def split_tuple(line):
    """Split one SQL VALUES tuple line into fields, respecting quotes."""
    assert line.startswith("(")
    out, buf, i, q = [], [], 1, False
    while i < len(line):
        c = line[i]
        if q:
            if c == "\\":
                buf.append(line[i + 1])
                i += 2
                continue
            if c == "'":
                q = False
            else:
                buf.append(c)
        elif c == "'":
            q = True
        elif c == ",":
            out.append("".join(buf))
            buf = []
        elif c == ")":
            out.append("".join(buf))
            return out
        else:
            buf.append(c)
        i += 1
    return out


def f32(bits):
    return struct.unpack("<f", struct.pack("<I", bits))[0]


# creaturedisplayinfoextra race id -> character/ folder
RACE_FOLDER = {1: "human", 2: "orc", 3: "dwarf", 4: "nightelf", 5: "scourge",
               6: "tauren", 7: "gnome", 8: "troll", 9: "goblin",
               10: "bloodelf", 11: "draenei", 22: "worgen"}
# flat colour for a hair geoset with no texture: dark brown reads as hair
# at a glance; untextured it rendered bright white (Mr. Smite's mane)
HAIR_FALLBACK_RGBA = (0.13, 0.09, 0.06, 1.0)

# name keyword -> stand-in model names, in preference order (see ok_models)
MODEL_STANDINS = [
    ("mordresh", ["Lich", "Ghost"]), ("summoner", ["Lich", "Ghost"]),
    ("frostweaver", ["Lich", "Ghost"]), ("skelet", ["Ghost", "Lich"]),
    ("splinterbone", ["Ghost"]), ("ironspine", ["Ghost"]), ("ghoul", ["Ghost"]),
    ("glutton", ["Ghost"]), ("anguished", ["Ghost"]), ("suffering", ["Ghost"]),
    ("fallen champion", ["Ghost"]), ("fairbanks", ["HumanMale", "Ghost"]),
    ("vorrel", ["HumanMale", "Ghost"]), ("thalnos", ["HumanMale", "Lich"]),
    ("shadowmage", ["HumanMale", "TrollMale", "NagaMale", "OrcFemale"]),
]

CREATURE_TYPES = {1: "beast", 2: "dragonkin", 3: "demon", 4: "elemental",
                  5: "giant", 6: "undead", 7: "humanoid", 8: "critter",
                  9: "mechanical", 11: "totem"}

# D2 gives every monster a resistance line-up and the WoW templates carry
# none, so the creature type sets a baseline and the name refines it: a
# Molten Elemental shrugs off fire and hates the cold, a skeleton cannot be
# poisoned. Percent; 100 is immune; negative is a weakness. The game applies
# them per damage type, less the character's "-N% to Enemy <element>
# Resistance" lines.
RESIST_BY_TYPE = {
    "elemental": {"fire": 50, "cold": 50, "ltng": 50, "pois": 100},
    "undead": {"cold": 75, "pois": 100},
    "demon": {"fire": 75, "pois": 25},
    "mechanical": {"fire": 25, "ltng": 25, "pois": 100},
    "totem": {"fire": 50, "cold": 50, "ltng": 50, "pois": 100},
    "dragonkin": {"fire": 50},
    "giant": {"fire": 25, "cold": 25},
    "beast": {"pois": 25},
}
# (whole words in the name, resists that override the baseline)
RESIST_BY_NAME = [
    (("molten", "fire", "flame", "lava", "magma", "blaze", "ember", "searing",
      "burning", "infernal"), {"fire": 100, "cold": -50}),
    (("frost", "ice", "frozen", "chill", "glacial", "snow"),
     {"cold": 100, "fire": -50}),
    (("water", "tide", "deep", "sea", "naga"), {"cold": 75, "ltng": -50}),
    (("earth", "stone", "rock", "crystal", "boulder"),
     {"ltng": 100, "pois": 100, "fire": 50}),
    (("storm", "thunder", "lightning", "spark", "static"),
     {"ltng": 100, "cold": -25}),
    (("shadow", "void", "dark", "shade", "spectral", "ghost", "phantom",
      "wraith"), {"cold": 50, "pois": 100}),
    (("slime", "ooze", "sludge", "ectoplasm"), {"pois": 100, "fire": -25}),
    (("mechanical", "mech", "golem", "shredder", "robot", "bomb"),
     {"pois": 100, "ltng": -25}),
]


# the name describes the creature itself for these types; for people and
# animals it names a faction (the Searing Blade orcs are not fireproof)
NAME_RESIST_TYPES = {"elemental", "totem", "undead", "mechanical", "giant", "other"}


def resistances(name, ctype):
    """The resistance dict for one creature: type baseline, name overrides."""
    res = dict(RESIST_BY_TYPE.get(ctype, {}))
    if ctype in NAME_RESIST_TYPES:
        words = set(re.findall(r"[a-z]+", name.lower()))
        for keys, over in RESIST_BY_NAME:
            if words & set(keys):
                res.update(over)
                break
    return {k: v for k, v in res.items() if v}


def nearest_blp(s, fdid, span=30):
    for off in range(1, span):
        for cand in (fdid + off, fdid - off):
            try:
                d = s.read_fdid(cand)
                if d[:4] == b"BLP2":
                    return cand
            except (CascError, KeyError):
                pass
    return None


# creature_template columns are looked up BY NAME from the dump's CREATE
# TABLE (see load_stats). They used to be hardcoded positions verified
# against one checkout; AzerothCore then dropped creature_template from 61
# columns to 55, so a build using freshly downloaded data read HealthModifier
# off the wrong field (always 0) and every creature — bosses included — came
# out with 0 HP. Names survive the reshuffle; positions don't.
# creature_classlevelstats: (level, class) -> row. Its leading columns are
# stable across the layouts seen (checked), so positions are kept here.
CLS_BASEHP0, CLS_ARMOR, CLS_AP, CLS_DMG_BASE = 2, 6, 7, 9


def xp_target(cfg):
    gd = json.loads((ASSETS / "gamedata.json").read_text())
    e = gd["experience"]
    hi = int(cfg["target_level"])
    # xp_span: how many levels a full clear is worth (5 by default; a wing
    # of a split dungeon carries its share of the whole)
    lo = max(1, hi - int(cfg.get("xp_span", 5)))
    return int(str(e[hi - 1])) - int(str(e[lo - 1]))


def gd_monlvl():
    gd = json.loads((ASSETS / "gamedata.json").read_text())
    rows = gd.get("monlvl", [])
    if not rows:
        raise SystemExit("gamedata.json has no monlvl table: re-run the D2 "
                         "table export (pipeline/d2/export_tables.py)")
    return rows


def load_stats(entries, spawns, cfg):
    """Parse AzerothCore SQL into per-entry D2-shaped stat rows."""
    cls = {}
    for m, line in sql_rows(AC / "creature_classlevelstats.sql", r"^\(\d+,"):
        f = split_tuple(line)
        cls[(int(f[0]), int(f[1]))] = f

    tpl = {}
    for m, line in sql_rows(AC / "creature_template.sql", r"^\(\d+,"):
        f = split_tuple(line)
        entry = int(f[0])
        if entry in entries:
            tpl[entry] = f

    # resolve the fields we read by name against this dump's actual layout
    cols = sql_columns(AC / "creature_template.sql")
    need = ["name", "minlevel", "maxlevel", "rank", "speed_run",
            "DamageModifier", "BaseAttackTime", "unit_class", "type",
            "HealthModifier", "ExperienceModifier"]
    missing = [c for c in need if c not in cols]
    if missing:
        raise RuntimeError(f"creature_template.sql lacks columns {missing}; "
                           "the AzerothCore schema changed again")
    ci = {c: cols.index(c) for c in need}
    CT_NAME, CT_MINLVL, CT_MAXLVL = ci["name"], ci["minlevel"], ci["maxlevel"]
    CT_RANK, CT_SPEED_RUN = ci["rank"], ci["speed_run"]
    CT_DMG_MOD, CT_ATK_TIME = ci["DamageModifier"], ci["BaseAttackTime"]
    CT_UNIT_CLASS, CT_TYPE = ci["unit_class"], ci["type"]
    CT_HP_MOD, CT_EXP_MOD = ci["HealthModifier"], ci["ExperienceModifier"]

    # bosses matched by name; report anything that didn't match
    boss_names = set(cfg.get("bosses", []))
    boss_entries = set()
    final_entry = -1
    for entry, f in tpl.items():
        nm = f[CT_NAME]
        if nm in boss_names:
            boss_entries.add(entry)
        if nm == cfg.get("final_boss", ""):
            final_entry = entry
    matched = {tpl[e][CT_NAME] for e in boss_entries}
    for nm in boss_names - matched:
        print(f"  !! boss name unmatched on this map: {nm!r}")
    if final_entry < 0:
        print(f"  !! FINAL BOSS unmatched: {cfg.get('final_boss')!r}")

    # auto level-band shift: mob mlvl should track the player band
    counts = {}
    for sp in spawns:
        counts[sp["entry"]] = counts.get(sp["entry"], 0) + 1
    lvl_sum = 0.0
    lvl_n = 0
    for e, n in counts.items():
        if e in tpl:
            lvl_sum += (int(tpl[e][CT_MINLVL]) + int(tpl[e][CT_MAXLVL])) / 2 * n
            lvl_n += n
    mean_wow = lvl_sum / max(1, lvl_n)
    band_player = int(cfg["target_level"]) - 2
    shift = int(round(mean_wow - band_player))
    print(f"level band: mean wow {mean_wow:.1f}, player ~{band_player}, "
          f"mlvl shift {shift}")

    # D2's own monster curve: MonLvl.txt gives HP / damage / AC / AR / XP per
    # monster level, and monstats scales each monster off it in percent. The
    # WoW template supplies that percent: a creature's health and damage
    # relative to its dungeon's average (rank and hp/dmg modifiers included),
    # clamped to the band D2's normal monsters use. So the same level-1
    # kobold in Ragefire and level-18 worgen in Shadowfang sit on one curve.
    monlvl = {int(r["Level"]): r for r in gd_monlvl()}

    def curve(m):
        return monlvl.get(max(1, min(99, m)), monlvl[max(monlvl)])

    wow_hp_of = {}
    wow_dph_of = {}
    for entry in entries:
        f = tpl.get(entry)
        if f is None:
            continue
        lvl = (int(f[CT_MINLVL]) + int(f[CT_MAXLVL])) // 2
        ucls = int(f[CT_UNIT_CLASS]) or 1
        crow = cls.get((lvl, ucls)) or cls.get((lvl, 1))
        if crow is None:
            continue
        atk_time = max(1.0, float(f[CT_ATK_TIME] or 2000) / 1000.0)
        wow_hp_of[entry] = int(crow[CLS_BASEHP0]) * float(f[CT_HP_MOD])
        wow_dph_of[entry] = ((float(crow[CLS_DMG_BASE]) + int(crow[CLS_AP]) / 14.0)
                             * atk_time * float(f[CT_DMG_MOD]))
    normals = [e for e in wow_hp_of if e not in boss_entries]
    mean_hp = sum(wow_hp_of[e] for e in normals) / max(1, len(normals))
    mean_dph = sum(wow_dph_of[e] for e in normals) / max(1, len(normals))

    stats = {}
    for entry in entries:
        f = tpl.get(entry)
        if f is None or entry not in wow_hp_of:
            continue
        lvl = (int(f[CT_MINLVL]) + int(f[CT_MAXLVL])) // 2
        ucls = int(f[CT_UNIT_CLASS]) or 1
        atk_time = max(1.0, float(f[CT_ATK_TIME] or 2000) / 1000.0)
        boss = entry in boss_entries
        mlvl = max(1, lvl - shift)
        if boss:
            mlvl += 3                  # D2 gives unique monsters +3 levels
        row = curve(mlvl)
        # relative toughness within the dungeon -> D2's monstats percent band
        hp_pct = wow_hp_of[entry] / max(1.0, mean_hp)
        dm_pct = wow_dph_of[entry] / max(1.0, mean_dph)
        if boss:
            hp_pct = min(6.0, max(3.0, hp_pct))    # super uniques: ~3-6x
            dm_pct = min(1.9, max(1.3, dm_pct))    # UniqueDamageBonus 90%
        else:
            hp_pct = min(1.5, max(0.55, hp_pct))
            dm_pct = min(1.5, max(0.55, dm_pct))
        hp = row["HP"] * hp_pct
        dm = row["DM"] * dm_pct
        vel = min(float(f[CT_SPEED_RUN]) * 7.0 * 0.9144 * 0.55, 4.2)
        archetype = "caster" if ucls == 8 else "melee"
        passive = int(f[CT_TYPE]) == 8          # critters ignore the player
        stats[entry] = {
            "wow_level": lvl,
            "Level": mlvl,
            "minHP": round(hp * 0.9, 1),
            "maxHP": round(hp * 1.1, 1),
            "A1MinD": round(dm * 0.6, 1),
            "A1MaxD": round(dm * 1.2, 1),
            "A1TH": row["TH"],
            "AC": row["AC"],
            "Velocity": round(vel, 2),
            "attack_time": round(atk_time, 2),
            "archetype": archetype,
            # creature_template.type, for the "+% damage to undead/demons"
            # item lines: 3 demon, 6 undead, 1 beast, 7 humanoid ...
            "ctype": CREATURE_TYPES.get(int(f[CT_TYPE]), "other"),
            "res": resistances(f[CT_NAME],
                               CREATURE_TYPES.get(int(f[CT_TYPE]), "other")),
            "passive": passive,
            "boss": boss,
            "final_boss": entry == final_entry,
            # drops are rolled in-game from the monster level and kind
            # (Act-band treasure classes, D2's quality algorithm)
            "kind": "final" if entry == final_entry else (
                "boss" if boss else ("champion" if int(f[CT_RANK]) > 0 else "normal")),
            "Exp": row["XP"] * float(f[CT_EXP_MOD])
                   * (1.5 if int(f[CT_RANK]) > 0 else 1.0)
                   * (3.0 if boss else 1.0),     # normalized below
        }

    total = sum(stats[e]["Exp"] * n for e, n in counts.items() if e in stats)
    scale = xp_target(cfg) / total if total else 1.0
    for e in stats:
        stats[e]["Exp"] = max(1, int(stats[e]["Exp"] * scale))
    print(f"xp normalize: scale {scale:.2f} "
          f"(clear target level {cfg['target_level']})")
    for e, n in sorted(counts.items()):
        if e in stats:
            st = stats[e]
            print(f"  {e:6d} x{n:3d} lvl{st['wow_level']} hp {st['minHP']:.0f}-"
                  f"{st['maxHP']:.0f} dmg {st['A1MinD']:.0f}-{st['A1MaxD']:.0f}"
                  f" xp {st['Exp']} {st['archetype']}"
                  f"{' BOSS' if st['boss'] else ''}"
                  f"{' FINAL' if st['final_boss'] else ''}")
    return stats


def build(s, dungeon_id, cfg, stats_only=False):
    spawns = load_spawns(cfg["ac_map"], cfg.get("wing"))
    entries = sorted({sp["entry"] for sp in spawns})
    print(f"{dungeon_id}: {len(spawns)} spawns, {len(entries)} unique entries")
    stats = load_stats(entries, spawns, cfg)
    out_dir = OUT / dungeon_id / "creatures"

    if stats_only:
        path = out_dir / "creatures.json"
        manifest = json.loads(path.read_text())
        for key in manifest:
            manifest[key]["stats"] = stats.get(int(key), {})
        path.write_text(json.dumps(manifest, indent=1))
        print(f"stats refreshed for {len(manifest)} creatures")
        return

    cdi = WDC5(s.read_path("dbfilesclient/creaturedisplayinfo.db2"))
    cmd = WDC5(s.read_path("dbfilesclient/creaturemodeldata.db2"))
    cde = WDC5(s.read_path("dbfilesclient/creaturedisplayinfoextra.db2"))
    slots = WDC5(s.read_path("dbfilesclient/npcmodelitemslotdisplayinfo.db2"))
    idi = WDC5(s.read_path("dbfilesclient/itemdisplayinfo.db2"))
    mfd = WDC5(s.read_path("dbfilesclient/modelfiledata.db2"))
    cmfd = WDC5(s.read_path("dbfilesclient/componentmodelfiledata.db2"))
    hairgeo = WDC5(s.read_path("dbfilesclient/charhairgeosets.db2"))
    mres_to_fdids = {}
    for rid, fid in mfd.relation.items():
        mres_to_fdids.setdefault(fid, []).append(rid)

    names, displays, equips = {}, {}, {}
    for m, line in sql_rows(AC / "creature_template.sql",
                            r"^\((\d+),(?:[^,]*,){5}'((?:[^'\\]|\\.)*)'"):
        names[int(m.group(1))] = m.group(2).replace("\\'", "'")
    for m, line in sql_rows(AC / "creature_template_model.sql",
                            r"^\((\d+), ?(\d+), ?(\d+),"):
        if int(m.group(2)) == 0:
            displays[int(m.group(1))] = int(m.group(3))
    for m, line in sql_rows(AC / "creature_equip_template.sql",
                            r"^\((\d+), ?(\d+), ?(\d+), ?(\d+), ?(\d+),"):
        if int(m.group(2)) == 1:
            equips[int(m.group(1))] = [int(m.group(3)), int(m.group(4)),
                                       int(m.group(5))]
    item_display = {}
    for m, line in sql_rows(AC / "item_template.sql",
                            r"^\((\d+), ?\d+, ?\d+, ?-?\d+, ?'(?:[^'\\]|\\.)*', ?(\d+),"):
        item_display[int(m.group(1))] = int(m.group(2))

    hand_tuned = {}
    for nm, specs in cfg.get("hand_tuned", {}).items():
        for entry, enm in names.items():
            if enm == nm:
                hand_tuned[entry] = specs

    def weapon_for_item(item_id):
        disp = item_display.get(item_id)
        if not disp or disp not in idi.rows:
            return None
        row = idi.rows[disp]
        mres = row[10][0] if isinstance(row[10], list) else row[10]
        fdids = mres_to_fdids.get(mres, [])
        if not fdids:
            return None
        model_fdid = fdids[0]
        tex = nearest_blp(s, model_fdid)
        return model_fdid, tex

    def helm_for_extra(extra_id, race, sex):
        for rid, row in slots.rows.items():
            if slots.relation.get(rid) == extra_id and row[1] == 0:
                disp = row[0]
                r2 = idi.rows.get(disp)
                if not r2:
                    return None
                mres = r2[10][0] if isinstance(r2[10], list) else r2[10]
                model = None
                for fd in mres_to_fdids.get(mres, []):
                    comp = cmfd.rows.get(fd)
                    if comp and comp[0] == sex and comp[2] == race:
                        model = fd
                        break
                if not model:
                    return None
                tex = DEFIAS_HELM_RED_TEX if disp == DEFIAS_HELM_DISPLAY \
                    else nearest_blp(s, model)
                return model, tex
        return None

    out_dir.mkdir(parents=True, exist_ok=True)
    # Which models the client actually holds. The anniversary client streams
    # creature models on demand, so a dungeon the player never visited can
    # be missing a few (Razorfen Downs' skeletons, the Scarlet graveyard's
    # spirits). Rather than leave a boss out, such a creature borrows the
    # nearest model the same dungeon does have, by name keyword.
    ok_models = {}
    for entry in entries:
        disp = displays.get(entry)
        row = cdi.rows.get(disp) if disp else None
        if not row:
            continue
        fd = cmd.rows[row[1]][2]
        if fd in ok_models:
            continue
        try:
            ok_models[fd] = M2Model(s.read_fdid(fd), lambda *a: None, s.read_fdid).name
        except (CascError, KeyError, ValueError, struct.error):
            pass
    avail = {}
    for fd, nm in ok_models.items():
        avail.setdefault(nm, fd)

    def standin(cname):
        low = cname.lower()
        for key, cands in MODEL_STANDINS:
            if key in low:
                for c in cands:
                    if c in avail:
                        return avail[c]
        return None

    manifest = {}
    for entry in entries:
        name = names.get(entry, "?")
        disp = displays.get(entry)
        row = cdi.rows.get(disp) if disp else None
        if not row:
            print(f"{entry} {name}: no display row, skipped")
            continue
        model_fdid = cmd.rows[row[1]][2]
        scale = f32(row[4]) or 1.0
        extra_id = row[7]
        if model_fdid not in ok_models:
            alt = standin(name)
            if alt is None:
                print(f"{entry} {name}: model {model_fdid} not in the local client, "
                      "no stand-in, skipped")
                continue
            print(f"{entry} {name}: model {model_fdid} not in the local client -> "
                  f"stand-in {ok_models[alt]}")
            model_fdid = alt
            extra_id = None       # its own textures, not the missing model's bake
        variations = row[25] if isinstance(row[25], list) else []
        def anim_resolver(seq_id, variation, afid):
            fd = afid.get((seq_id, variation))
            if fd:
                try:
                    return s.read_fdid(fd)
                except CascError:
                    return None
            return None

        try:
            model = M2Model(s.read_fdid(model_fdid), anim_resolver,
                            s.read_fdid)
            skin = Skin(s.read_fdid(model.sfid[0]))
        except (CascError, KeyError, ValueError, struct.error) as e:
            print(f"{entry} {name}: model {model_fdid} failed: {e}")
            continue

        textures, geosets = {}, None
        flat_colors = {}      # texture slot -> RGBA when no texture can be found
        if extra_id and extra_id in cde.rows:
            erow = cde.rows[extra_id]
            race, sex, style = erow[1], erow[2], erow[5]
            baked = s.root.fdid_for_path(
                f"textures/bakednpctextures/creaturedisplayextra-{extra_id:05d}.blp")
            hair_geoset = 0
            for rid, hrow in hairgeo.rows.items():
                if hrow[0] == race and hrow[1] == sex and hrow[2] == style:
                    hair_geoset = hrow[3]
                    break
            geosets = {0, hair_geoset, 101, 201, 301, 401, 501, 702, 1301}
            folder = RACE_FOLDER.get(race, "")
            sexdir = "female" if sex == 1 else "male"
            # hair: a per-race texture exists for the classic races; tauren,
            # goblin and worgen keep theirs elsewhere (no readable path under
            # any naming probed), so their hair falls back to a flat dark
            # colour below rather than rendering untextured white
            hair_tex = s.root.fdid_for_path(f"character/{folder}/hair00_00.blp") \
                if folder else None
            # body: the baked NPC texture, or — when that file is not in the
            # local client (named in the root but never streamed, which is
            # the common case) — the race's base skin, so the body is not
            # left grey
            skin_fallback = s.root.fdid_for_path(
                f"character/{folder}/{sexdir}/{folder}{sexdir}skin00_00.blp") \
                if folder else None
            for i, tex in enumerate(model.textures):
                if tex["type"] == 1:
                    for cand in (baked, skin_fallback):
                        if not cand:
                            continue
                        try:
                            textures[i] = blp_to_png(s.read_fdid(cand))
                            break
                        except CascError:
                            continue
                elif tex["type"] == 6 and hair_tex:
                    try:
                        textures[i] = blp_to_png(s.read_fdid(hair_tex))
                    except CascError:
                        pass
                elif tex["type"] == 0 and i < len(model.txid) and model.txid[i]:
                    textures[i] = blp_to_png(s.read_fdid(model.txid[i]))
            # whatever slot is still bare (hair on races with no readable hair
            # texture, and whichever type the tauren mane uses) renders as a
            # flat dark colour instead of untextured white
            for i in range(len(model.textures)):
                if i not in textures:
                    flat_colors[i] = HAIR_FALLBACK_RGBA
        else:
            vi = 0
            for i, tex in enumerate(model.textures):
                fd = None
                if tex["type"] == 0 and i < len(model.txid) and model.txid[i]:
                    fd = model.txid[i]
                elif tex["type"] in (11, 12, 13):
                    while vi < len(variations) and not variations[vi]:
                        vi += 1
                    if vi < len(variations):
                        fd = variations[vi]
                        vi += 1
                if fd:
                    try:
                        textures[i] = blp_to_png(s.read_fdid(fd))
                    except CascError:
                        pass

        attachments = []
        specs = hand_tuned.get(entry)
        if specs is None:
            specs = []
            items = equips.get(entry, [])
            for slot_i, item_id in enumerate(items[:2]):
                if not item_id:
                    continue
                w = weapon_for_item(item_id)
                if w:
                    specs.append((slot_i + 1, w[0], w[1]))
        else:
            specs = list(specs)
        # the head item regardless of how the hands were chosen: hand-tuned
        # weapons used to replace the whole list, which is why VanCleef lost
        # the same Defias bandana every pirate around him was wearing
        if extra_id and extra_id in cde.rows:
            h = helm_for_extra(extra_id, cde.rows[extra_id][1],
                               cde.rows[extra_id][2])
            if h:
                specs.append((11, h[0], h[1]))
        for attach_id, wfdid, wtex in specs:
            try:
                wm = M2Model(s.read_fdid(wfdid))
                wskin = Skin(s.read_fdid(wm.sfid[0]))
                wt = {}
                for i, tex in enumerate(wm.textures):
                    fd = None
                    if tex["type"] == 0 and i < len(wm.txid) and wm.txid[i]:
                        fd = wm.txid[i]
                    elif tex["type"] != 0 and wtex:
                        fd = wtex
                    if fd:
                        try:
                            wt[i] = blp_to_png(s.read_fdid(fd))
                        except CascError:
                            pass
                attachments.append({"attach_id": attach_id, "model": wm,
                                    "skin": wskin, "textures": wt})
            except (CascError, KeyError, ValueError, struct.error) as e:
                print(f"  weapon {wfdid}: {e}")

        dest = out_dir / f"{entry}.glb"
        try:
            info = gltf_export.export_glb(
                model, skin, textures, dest, seq_filter=GAME_SEQS,
                allowed_geosets=geosets, attachments=attachments,
                flat_colors=flat_colors)
            if not info["animations"]:
                info = gltf_export.export_glb(
                    model, skin, textures, dest, seq_filter=None,
                    allowed_geosets=geosets, attachments=attachments,
                    flat_colors=flat_colors)
        except (CascError, KeyError, ValueError, struct.error) as e:
            print(f"{entry} {name}: export failed: {e}")
            continue
        # voice family: by model, overridable per entry from dungeon_config
        # (an undead HumanMale in Shadowfang should not sound like a Defias
        # miner). Families are the keys of build_audio.CREATURE_SFX.
        voice = cfg.get("voices", {}).get(entry) \
            or VOICE_BY_MODEL.get(model.name, "")
        manifest[entry] = {"name": name, "scale": scale,
                           "model": model.name, "voice": voice,
                           "anims": info["animations"],
                           "stats": stats.get(entry, {})}
        print(f"{entry} {name}: {model.name} scale={scale:.2f} "
              f"{len(textures)} tex, {len(attachments)} attach, "
              f"{info['size']//1024} KB, {len(info['animations'])} anims")

    with open(out_dir / "creatures.json", "w") as f:
        json.dump(manifest, f, indent=1)
    print(f"\n{len(manifest)}/{len(entries)} creatures exported")


def main():
    ap = argparse.ArgumentParser()
    # required, not defaulted: a bare run used to quietly rebuild the Deadmines
    ap.add_argument("--dungeon", required=True, choices=sorted(DUNGEONS),
                    help="dungeon id to build creatures for")
    ap.add_argument("--stats-only", action="store_true",
                    help="retune creatures.json without re-exporting models")
    args = ap.parse_args()
    cfg = DUNGEONS[args.dungeon]
    s = None if args.stats_only else Storage()
    build(s, args.dungeon, cfg, stats_only=args.stats_only)


if __name__ == "__main__":
    main()
