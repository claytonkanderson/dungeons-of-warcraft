"""Export a GLB per unique Deadmines creature with the full gameplay
animation set, plus D2-shaped combat stats derived from AzerothCore data.

Model/texture/attachment resolution is the warcraft-art recipe:
creature_template_model -> display -> model fdid (+ scale); humanoids get
baked NPC texture, hair geoset, and the Defias bandana when their helm slot
says so; equipment becomes rigid hand attachments. Weapon/helm skins that
need the (missing) texturefiledata.db2 fall back to the nearest BLP in the
model's fdid neighborhood.

New in this repo:
- seq_filter covers Stand/Death/Walk/Run/wounds/attacks/casts so the game
  can drive a real AI state machine off the clips.
- creatures.json carries per-entry stats mapped into the D2 combat model
  (the fields wow_creature.gd reads), XP normalized so a full clear of the
  213 spawns lands the Amazon around level 20.
"""
import json
import re
import struct
from pathlib import Path

from config import OUT, AC, ASSETS
from casc import Storage, CascError
from db2 import WDC5
from m2 import M2Model, Skin
from blp import blp_to_png
import gltf_export

DEFIAS_HELM_DISPLAY = 15308
DEFIAS_HELM_RED_TEX = 138220

ENTRIES = [598, 622, 634, 636, 639, 641, 642, 644, 645, 646, 647, 657,
           1725, 1729, 1731, 1732, 1763, 3586, 3947, 4075, 4416, 4417, 4418]

# VanCleef keeps his hand-tuned build (correct sword skins, black hair)
HAND_TUNED = {
    639: dict(weapons=[(1, 148115, 148117), (2, 148120, 148124)]),
}

# gameplay animation sequences: stand, death, locomotion, wounds,
# melee attacks, spell casts
GAME_SEQS = {0, 1, 4, 5, 9, 10, 16, 17, 18, 19, 31, 32, 51}

# --- D2 stat mapping tuning -------------------------------------------------
# Player starts at level 14 with starter gear; skills carry the damage.
# Trash ~4 plain arrows / 1-2 skill arrows, elites meaty, bosses long.
HP_TUNE = 0.18        # wow hp -> D2 hp (lvl-17 trash ~390 -> ~70)
DMG_TUNE = 0.60       # wow damage/hit -> D2 damage (trash ~25 -> ~15)
MLVL_SHIFT = 4        # wow level - shift = D2 mlvl (matches plvl 14 start)
START_LEVEL = 14      # xp normalized so a full clear runs 14 -> ~TARGET_LEVEL
TARGET_LEVEL = 28


def xp_target():
    gd = json.loads((ASSETS / "gamedata.json").read_text())
    e = gd["experience"]
    return int(str(e[TARGET_LEVEL])) - int(str(e[START_LEVEL - 1]))


def sql_rows(path, pattern):
    pat = re.compile(pattern)
    for line in path.read_text(encoding="utf-8").splitlines():
        m = pat.match(line)
        if m:
            yield m, line


def split_tuple(line):
    """Split one SQL VALUES tuple line "(a,b,'c, d',...)," into fields,
    respecting single-quoted strings with backslash escapes."""
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


def nearest_blp(s, fdid, span=10):
    for off in range(1, span):
        for cand in (fdid + off, fdid - off):
            try:
                d = s.read_fdid(cand)
                if d[:4] == b"BLP2":
                    return cand
            except (CascError, KeyError):
                pass
    return None


# creature_template column indices (verified against the CREATE TABLE)
CT_NAME, CT_MINLVL, CT_MAXLVL, CT_RANK = 6, 10, 11, 21
CT_SPEED_RUN, CT_DMG_MOD, CT_ATK_TIME, CT_UNIT_CLASS = 16, 23, 24, 28
CT_TYPE, CT_HP_MOD, CT_EXP_MOD = 37, 49, 52

# In-instance every Defias is rank "elite"; actual dungeon bosses are these
# (VanCleef, Sneed, Rhahk'Zor, Cookie, Smite, Greenskin, Gilnid, Miner Johnson)
BOSSES = {639, 642, 644, 645, 646, 647, 1763, 3586}
# creature_classlevelstats: (level, class) -> row
CLS_BASEHP0, CLS_ARMOR, CLS_AP, CLS_DMG_BASE = 2, 6, 7, 9


def load_stats():
    """Parse AzerothCore SQL into per-entry D2-shaped stat rows."""
    cls = {}
    for m, line in sql_rows(AC / "creature_classlevelstats.sql", r"^\(\d+,"):
        f = split_tuple(line)
        cls[(int(f[0]), int(f[1]))] = f

    tpl = {}
    for m, line in sql_rows(AC / "creature_template.sql", r"^\(\d+,"):
        f = split_tuple(line)
        entry = int(f[0])
        if entry in ENTRIES:
            tpl[entry] = f

    stats = {}
    for entry in ENTRIES:
        f = tpl.get(entry)
        if f is None:
            continue
        lvl = (int(f[CT_MINLVL]) + int(f[CT_MAXLVL])) // 2
        ucls = int(f[CT_UNIT_CLASS]) or 1
        crow = cls.get((lvl, ucls)) or cls.get((lvl, 1))
        hp_mod = float(f[CT_HP_MOD])
        dmg_mod = float(f[CT_DMG_MOD])
        atk_time = max(1.0, float(f[CT_ATK_TIME] or 2000) / 1000.0)
        wow_hp = int(crow[CLS_BASEHP0]) * hp_mod
        wow_dph = (float(crow[CLS_DMG_BASE])
                   + int(crow[CLS_AP]) / 14.0) * atk_time * dmg_mod
        rank = int(f[CT_RANK])
        mlvl = max(1, lvl - MLVL_SHIFT)
        # speed_run is a multiplier of the 7 yd/s base run speed
        vel = min(float(f[CT_SPEED_RUN]) * 7.0 * 0.9144 * 0.55, 4.2)
        archetype = "caster" if ucls == 8 else "melee"
        passive = int(f[CT_TYPE]) == 8          # critters ignore the player
        boss = entry in BOSSES
        if entry == 639:
            tc = "Andariel"                      # the kingpin drops like a queen
        elif boss:
            tc = "Act 1 Unique B"
        elif archetype == "caster":
            tc = "Act 1 Cast B"
        else:
            tc = "Act 1 Melee B"
        stats[entry] = {
            "wow_level": lvl,
            "Level": mlvl,
            "minHP": round(wow_hp * HP_TUNE * 0.9, 1),
            "maxHP": round(wow_hp * HP_TUNE * 1.1, 1),
            "A1MinD": round(wow_dph * DMG_TUNE * 0.75, 1),
            "A1MaxD": round(wow_dph * DMG_TUNE * 1.25, 1),
            "A1TH": 30 + 6 * mlvl,
            "AC": 6 + 4 * mlvl,
            "Velocity": round(vel, 2),
            "attack_time": round(atk_time, 2),
            "archetype": archetype,
            "passive": passive,
            "boss": boss,
            "final_boss": entry == 639,
            "TC": tc,
            "Exp": (5 * lvl + 45) * float(f[CT_EXP_MOD])
                   * (1.5 if rank > 0 else 1.0)
                   * (3.0 if boss else 1.0),     # normalized below
        }

    # XP normalization against the real spawn list + the D2 exp table
    counts = {}
    pl = json.loads((OUT / "deadmines" / "placements.json").read_text())
    for c in pl.get("creatures", []):
        counts[int(c["entry"])] = counts.get(int(c["entry"]), 0) + 1
    total = sum(stats[e]["Exp"] * n for e, n in counts.items() if e in stats)
    scale = xp_target() / total if total else 1.0
    for e in stats:
        stats[e]["Exp"] = max(1, int(stats[e]["Exp"] * scale))
    print(f"xp normalize: raw total {total:.0f} -> scale {scale:.2f}")
    for e, n in sorted(counts.items()):
        if e in stats:
            st = stats[e]
            print(f"  {e:5d} x{n:3d} lvl{st['wow_level']} hp {st['minHP']:.0f}-"
                  f"{st['maxHP']:.0f} dmg {st['A1MinD']:.0f}-{st['A1MaxD']:.0f}"
                  f" xp {st['Exp']} {st['archetype']}"
                  f"{' BOSS' if st['boss'] else ''}")
    return stats


def stats_only():
    """Rewrite creatures.json stats without re-exporting the GLBs."""
    stats = load_stats()
    path = OUT / "deadmines" / "creatures" / "creatures.json"
    manifest = json.loads(path.read_text())
    for key in manifest:
        manifest[key]["stats"] = stats.get(int(key), {})
    path.write_text(json.dumps(manifest, indent=1))
    print(f"stats refreshed for {len(manifest)} creatures")


def main():
    stats = load_stats()
    s = Storage()
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

    out_dir = OUT / "deadmines" / "creatures"
    out_dir.mkdir(parents=True, exist_ok=True)
    manifest = {}
    for entry in ENTRIES:
        name = names.get(entry, "?")
        disp = displays.get(entry)
        row = cdi.rows.get(disp) if disp else None
        if not row:
            print(f"{entry} {name}: no display row, skipped")
            continue
        model_fdid = cmd.rows[row[1]][2]
        scale = f32(row[4]) or 1.0
        extra_id = row[7]
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
        except (CascError, KeyError, ValueError) as e:
            print(f"{entry} {name}: model {model_fdid} failed: {e}")
            continue

        textures, geosets = {}, None
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
            hair_tex = s.root.fdid_for_path("character/human/hair00_00.blp") \
                if race == 1 else None
            for i, tex in enumerate(model.textures):
                if tex["type"] == 1 and baked:
                    textures[i] = blp_to_png(s.read_fdid(baked))
                elif tex["type"] == 6 and hair_tex:
                    textures[i] = blp_to_png(s.read_fdid(hair_tex))
                elif tex["type"] == 0 and i < len(model.txid) and model.txid[i]:
                    textures[i] = blp_to_png(s.read_fdid(model.txid[i]))
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
        specs = HAND_TUNED.get(entry, {}).get("weapons")
        if specs is None:
            specs = []
            items = equips.get(entry, [])
            for slot_i, item_id in enumerate(items[:2]):
                if not item_id:
                    continue
                w = weapon_for_item(item_id)
                if w:
                    specs.append((slot_i + 1, w[0], w[1]))
            if extra_id:
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
            except (CascError, KeyError, ValueError) as e:
                print(f"  weapon {wfdid}: {e}")

        dest = out_dir / f"{entry}.glb"
        info = gltf_export.export_glb(
            model, skin, textures, dest, seq_filter=GAME_SEQS,
            allowed_geosets=geosets, attachments=attachments)
        if not info["animations"]:  # model without any of the game sequences
            info = gltf_export.export_glb(
                model, skin, textures, dest, seq_filter=None,
                allowed_geosets=geosets, attachments=attachments)
        manifest[entry] = {"name": name, "scale": scale,
                           "anims": info["animations"],
                           "stats": stats.get(entry, {})}
        print(f"{entry} {name}: {model.name} scale={scale:.2f} "
              f"{len(textures)} tex, {len(attachments)} attach, "
              f"{info['size']//1024} KB, anims={info['animations']}")

    with open(out_dir / "creatures.json", "w") as f:
        json.dump(manifest, f, indent=1)
    print(f"\n{len(manifest)} creatures exported")


if __name__ == "__main__":
    import sys
    if "--stats-only" in sys.argv:
        stats_only()
    else:
        main()
