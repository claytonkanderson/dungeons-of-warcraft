"""Trim the AzerothCore world-database dumps to what the configured dungeons
need, and write them to pipeline/ac_data/ (committed, shipped inside
setup.exe).

The full dumps are ~50 MB and were downloaded at install time; the four
dungeons touch a few thousand rows of them. Trimming keeps every table's
CREATE TABLE header (the column layout the readers resolve names against)
and only the rows for the instance maps in dungeon_config, plus whatever
those rows reference: creature templates and models for spawned entries,
equipment and the items it names, gameobject templates for placed objects.
The two small lookup tables travel whole.

    python pipeline/trim_ac.py [--ac <full db_world dir>]

Re-run after adding a dungeon to dungeon_config, or after refreshing the
full dumps (setup.exe --refresh-ac downloads them to _build/assets/_accache).
"""
import argparse
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from dungeon_common import sql_columns          # noqa: E402
from dungeon_config import DUNGEONS             # noqa: E402

OUT = HERE / "ac_data"
WHOLE = ["creature_classlevelstats.sql", "areatrigger_teleport.sql"]


def split_tuple(line):
    """One SQL VALUES tuple line -> fields, respecting quotes."""
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


def trim(src, dest, keep):
    """Copy the dump keeping the header and the tuple lines keep() accepts.
    Returns the kept rows (as field lists) for the next table's predicate."""
    header = []
    rows = []
    kept = []
    seen_insert = False
    for line in src.read_text(encoding="utf-8").splitlines():
        if line.startswith("("):
            body = line.rstrip()
            if body.endswith(",") or body.endswith(";"):
                body = body[:-1]
            f = split_tuple(body)
            if keep(f):
                rows.append(body)
                kept.append(f)
        elif line.startswith("INSERT INTO"):
            if not seen_insert:
                header.append(line)
                seen_insert = True
        elif not rows:
            header.append(line)
    text = "\n".join(header)
    if rows:
        text += "\n" + ",\n".join(rows) + ";\n"
    else:
        # an INSERT with no rows is a syntax error; drop the statement
        text = "\n".join(h for h in header if not h.startswith("INSERT INTO")) + "\n"
    dest.write_text(text, encoding="utf-8")
    print(f"{src.name:32s} {len(kept):6d} rows  {dest.stat().st_size / 1024:7.0f} KB")
    return kept


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ac", default="", help="full AzerothCore db_world dir")
    a = ap.parse_args()
    if a.ac:
        ac = Path(a.ac)
    else:
        from config import AC as ac
    OUT.mkdir(exist_ok=True)
    maps = {str(cfg["ac_map"]) for cfg in DUNGEONS.values()}
    print(f"maps: {sorted(maps)}  from {ac}")

    def col(table):
        cols = sql_columns(ac / f"{table}.sql")
        return lambda name: cols.index(name)

    c = col("creature")
    creatures = trim(ac / "creature.sql", OUT / "creature.sql",
                     lambda f: f[c("map")] in maps)
    entries = set()
    for f in creatures:
        for k in ("id1", "id2", "id3"):
            v = f[c(k)]
            if v not in ("", "0"):
                entries.add(v)
    # bosses and final bosses named in the config are spawned already; the
    # template of anything a dungeon script summons is not, and is not needed
    t = col("creature_template")
    trim(ac / "creature_template.sql", OUT / "creature_template.sql",
         lambda f: f[t("entry")] in entries)
    m = col("creature_template_model")
    trim(ac / "creature_template_model.sql", OUT / "creature_template_model.sql",
         lambda f: f[m("CreatureID")] in entries)
    e = col("creature_equip_template")
    equips = trim(ac / "creature_equip_template.sql", OUT / "creature_equip_template.sql",
                  lambda f: f[e("CreatureID")] in entries)
    items = set()
    for f in equips:
        for k in ("ItemID1", "ItemID2", "ItemID3"):
            v = f[e(k)]
            if v not in ("", "0"):
                items.add(v)
    # hand-tuned equipment in dungeon_config names display ids, not items
    it = col("item_template")
    trim(ac / "item_template.sql", OUT / "item_template.sql",
         lambda f: f[it("entry")] in items)
    g = col("gameobject")
    gobs = trim(ac / "gameobject.sql", OUT / "gameobject.sql",
                lambda f: f[g("map")] in maps)
    gids = {f[g("id")] for f in gobs}
    gt = col("gameobject_template")
    trim(ac / "gameobject_template.sql", OUT / "gameobject_template.sql",
         lambda f: f[gt("entry")] in gids)
    for name in WHOLE:
        trim(ac / name, OUT / name, lambda f: True)
    print(f"-> {OUT}")


if __name__ == "__main__":
    main()
