"""Dungeons of Warcraft asset builder.

Generates every game asset from the player's OWN installs — nothing from
Blizzard ships with the game. Requires:

  - Diablo II (1.14 or an install with the classic MPQs in its folder)
  - World of Warcraft Classic Anniversary (the local game data)

Usage:
  python builder.py --d2 "C:\\Program Files (x86)\\Diablo II" ^
                    --wow "C:\\Program Files (x86)\\World of Warcraft" ^
                    [--out <assets dir>] [--ac <azerothcore db_world dir>]

Spawn/stat data comes from the open-source AzerothCore project (AGPL);
when no local checkout is given, the needed SQL files are downloaded from
GitHub at build time.
"""
import argparse
import os
import sys
import time
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent

AC_FILES = [
    "creature.sql", "creature_template.sql", "creature_template_model.sql",
    "creature_equip_template.sql", "item_template.sql",
    "creature_classlevelstats.sql", "areatrigger_teleport.sql",
]
AC_URL = ("https://raw.githubusercontent.com/azerothcore/azerothcore-wotlk/"
          "master/data/sql/base/db_world/")


def fail(msg):
    print(f"\nERROR: {msg}")
    sys.exit(1)


def check_d2(d2):
    for probe in ["patch_d2.mpq", "d2data.mpq"]:
        if not (Path(d2) / probe).exists():
            fail(f"{probe} not found in {d2} — point --d2 at the Diablo II "
                 "install folder that contains the .mpq files")


def check_wow(wow):
    if not (Path(wow) / "Data").is_dir():
        fail(f"no Data/ directory in {wow} — point --wow at the WoW Classic "
             "Anniversary install (the folder containing Data and .build.info)")


def ensure_ac(ac_dir, cache):
    if ac_dir and Path(ac_dir, "creature.sql").exists():
        return Path(ac_dir)
    cache.mkdir(parents=True, exist_ok=True)
    for f in AC_FILES:
        dest = cache / f
        if dest.exists() and dest.stat().st_size > 0:
            continue
        print(f"downloading AzerothCore data: {f} ...")
        urllib.request.urlretrieve(AC_URL + f, dest)
    return cache


def run_d2_stages():
    sys.path.insert(0, str(HERE / "d2"))
    import export_tables
    import export_ui
    import export_missiles
    import export_amazon
    import export_paperdoll
    import export_monsters
    import export_items
    import export_affixes
    import export_statdisplay
    import export_sounds
    stages = [
        ("game tables", export_tables.build),
        ("D2 interface art", export_ui.build),
        ("missile sprites", export_missiles.build),
        ("Amazon animation sheets", export_amazon.build),
        ("menu paperdoll layers", export_paperdoll.build),
        ("summon sprites", lambda: (
            setattr(export_monsters, "ROSTER", {"VK": "valkyrie"}),
            export_monsters.build())),
        ("item catalog + art", export_items.build),
        ("uniques / sets / affixes", export_affixes.build),
        ("item stat text + font", lambda: (
            export_statdisplay.export_font("font16"),
            export_statdisplay.export_statdisplay())),
        ("D2 sound effects", export_sounds.build),
    ]
    for label, fn in stages:
        t0 = time.time()
        print(f"\n--- D2: {label} ---")
        fn()
        print(f"    ({time.time() - t0:.0f}s)")
    import export_setbonus
    print("\n--- D2: set bonuses ---")
    export_setbonus.main()


def run_wow_stages(only=""):
    sys.path.insert(0, str(HERE))
    # the D2 stages import their own module also named "config"; make sure
    # the WoW stages resolve pipeline/config.py fresh
    sys.modules.pop("config", None)
    import build_dungeon
    import build_audio
    import build_backdrops
    from casc import Storage
    from dungeon_config import DUNGEONS
    print("\n--- WoW: opening local game storage ---")
    s = Storage()
    for did, cfg in DUNGEONS.items():
        if only and did != only:
            continue
        t0 = time.time()
        print(f"\n--- WoW: {did} ---")
        build_dungeon.build(s, did, cfg)
        print(f"    ({time.time() - t0:.0f}s)")
    print("\n--- WoW: menu backdrops ---")
    build_backdrops.build(s)
    print("\n--- WoW: soundscape ---")
    build_audio.main()


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--d2", required=True, help="Diablo II install folder")
    ap.add_argument("--wow", required=True,
                    help="WoW Classic Anniversary install folder")
    ap.add_argument("--out", default="",
                    help="assets output dir (default: ./assets beside the game)")
    ap.add_argument("--ac", default="",
                    help="local AzerothCore db_world dir (else downloaded)")
    ap.add_argument("--skip-d2", action="store_true")
    ap.add_argument("--skip-wow", action="store_true")
    ap.add_argument("--only-dungeon", default="", help=argparse.SUPPRESS)
    args = ap.parse_args()

    check_d2(args.d2)
    check_wow(args.wow)
    out = Path(args.out) if args.out else HERE.parent / "assets"
    out.mkdir(parents=True, exist_ok=True)
    ac = ensure_ac(args.ac, out / "_accache")

    os.environ["DOW_D2_DIR"] = str(Path(args.d2))
    os.environ["DOW_WOW_ROOT"] = str(Path(args.wow))
    os.environ["DOW_ASSETS"] = str(out)
    os.environ["DOW_AC_DIR"] = str(ac)

    t0 = time.time()
    if not args.skip_d2:
        run_d2_stages()
    if not args.skip_wow:
        run_wow_stages(args.only_dungeon)
    print(f"\nALL DONE in {(time.time() - t0) / 60:.1f} min -> {out}")
    print("Launch the game — the dungeon ladder is waiting.")


if __name__ == "__main__":
    main()
