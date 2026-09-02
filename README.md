# Dungeons of Warcraft

*a Diablo / Warcraft hybrid mod*

Vanilla World of Warcraft dungeons, played first-person as a Diablo II
Amazon. Godot 4.7, with every asset generated on your own machine from your
own two game installs — nothing from either game ships here.

- **Environment** — real WoW instances: WMOs, hundreds of doodads and props,
  terrain, water and waterfalls, extracted through a pure-Python CASC
  pipeline (no listfile; filenames are recovered by jenkins96 hashing).
- **Interface** — Diablo II's control panel, orbs, inventory, character
  sheet, skill tree, item tooltips and bitmap font, decoded from the MPQs.
- **Class and abilities** — the D2 Amazon: three skill trees, weapon
  classes, D2 combat math, stats and leveling. Characters start at 14 with
  14 skill points and 70 stat points unspent.
- **Enemies** — every AzerothCore creature spawn as an animated WoW model
  with chase/attack AI, LOS-gated aggro and its own voice set; stats derived
  from `creature_template` and `creature_classlevelstats`.
- **Loot** — D2 drop generation: treasure classes, uniques, sets with set
  bonuses, rares and magic rolls with authentic tooltip text, gated by your
  level so drops stay usable.

Progress runs along the vanilla 1–60 dungeon ladder. Each character has
their own save and their own unlocks; killing a dungeon's final boss opens
the next.

**Built so far:** Ragefire Chasm (13–18), Wailing Caverns (15–25), The
Deadmines (17–26), Shadowfang Keep (22–30). The remaining sixteen are listed
in the menu and arrive as they get built.

## Play

You need two of your own installs:

- **Diablo II** — any install whose folder holds the classic `d2data.mpq`
  and `patch_d2.mpq` (1.14, or the disc/installer build). Diablo II:
  Resurrected does not ship these archives.
- **World of Warcraft Classic Anniversary** — the `wow_anniversary` product
  (2.5.x; built and tested against `2.5.6.69546`), with its data **fully
  downloaded**. The client streams on demand, so let Battle.net finish the
  download first — a partial install is missing files the build needs. Other
  clients (retail, Classic Era, Season of Discovery, Wrath/Cata Classic)
  won't work.

From the portable build — how other people install it: double-click
`setup.exe` for a window that picks the two install folders and runs the
build, or drive it from the command line:

```bash
setup.exe --d2 "C:\Path\To\Diablo II" --wow "C:\Path\To\World of Warcraft"
```

`--d2` points at the folder containing `d2data.mpq`; `--wow` at the folder
containing `Data\` and `.build.info`. Either way it writes everything it
generates into `_build\` next to the executables — `_build\assets` (about
600 MB, 10–20 minutes; the first build fetches AzerothCore data over the
internet), plus `setup.log` and the remembered paths — after which
`DungeonsOfWarcraft.exe` runs. From a source checkout, `run_game.bat`
launches the Godot build directly against the repo's `assets/`.

| | |
|---|---|
| WASD + mouse | move, look |
| Shift | run (stamina) |
| Space | jump |
| LMB / RMB | the two D2 action slots |
| 1–4 | belt potions |
| F1–F5 | swap the RMB skill |
| T | skill tree — click to spend, ctrl-click binds LMB, right-click binds RMB, hover and press F1–F5 to bind a hotkey |
| I / C | inventory, character sheet |
| E | interact, or pick up the nearest item |
| Alt | show loot labels |
| F9 | manual save |
| Esc | close panels, then the menu |

Characters live in `%APPDATA%\Godot\app_userdata\Dungeons of Warcraft\
characters\`, one JSON file each, safe to copy.

## Building the assets

`assets/` is git-ignored and never committed — it is derived entirely from
your installs. The pipeline needs Pillow and numpy:

```bash
pip install pillow numpy
```

One command then rebuilds all of it:

```bash
python pipeline/builder.py --d2 "C:\Path\To\Diablo II" --wow "C:\Path\To\World of Warcraft"
```

The D2 stages decode MPQ archives (tables, interface art, Amazon animation
sheets, paperdoll layers, item catalog and sprites, uniques/sets/affixes,
sound effects). The WoW stages open the CASC storage and build each
configured dungeon, then the soundscape and the menu backdrops. Creature
spawns and stats come from nine AzerothCore `.sql` files, downloaded from
their repository at build time unless you point `--ac` at a local copy.
`--skip-d2` and `--skip-wow` run one half.

Individual stages, for iterating on one thing:

```bash
python pipeline/build_dungeon.py --dungeon shadowfang-keep   # or --all
python pipeline/build_creatures.py --dungeon deadmines --stats-only
python pipeline/build_backdrops.py                            # all 20 menu backdrops
python pipeline/build_audio.py
python pipeline/d2/build_assets.py                            # every D2 stage
```

Adding a dungeon means one entry in `pipeline/dungeon_config.py` — map name,
AzerothCore map id, target level, boss names, and any door or lever rules —
and then `build_dungeon.py --dungeon <id>`. Install paths come from
environment variables (`DOW_D2_DIR`, `DOW_WOW_ROOT`, `DOW_ASSETS`,
`DOW_AC_DIR`) with dev-machine defaults in `pipeline/config.py` and
`pipeline/d2/config.py`.

## Architecture

The Godot project builds its scenes in code; the `.tscn` files are stubs and
there are no imported resources. Assets load from the filesystem at runtime
through `Paths.root()`, which resolves to `../assets` in the editor and
`_build/assets` beside the executable in an exported build.

- `world.gd` — the main scene: placements, terrain, creatures, gameobjects;
  combat resolution (collision-based arrows, melee cleave scaled to weapon
  size, skill AoE, enemy missiles), loot, doors and levers.
- `wow_creature.gd` — a WoW creature: GLB visual plus AnimationPlayer, a
  state machine over D2 stats, LOS-gated aggro, and a dormancy LOD that
  disables distant idle creatures to hold 60 fps.
- `player.gd` — movement and warp-based mouse look (pointer capture is
  unreliable on this machine, so look is accumulated from relative motion
  with warp compensation).
- `main_menu.gd`, `paperdoll.gd` — the roster and ladder, the selected
  character composited from D2 equipment layers, per-dungeon backdrops.
- `game_state.gd` — characters, equipment, set bonuses, stats, saves.
- `item_db.gd`, `item_gen.gd`, `item_text.gd`, `inventory_ui.gd`,
  `char_sheet.gd`, `skill_tree_ui.gd`, `hud.gd` — the D2 item and UI layer.
- `sfx.gd` (D2 effects), `wow_sfx.gd` (creature voices, impacts),
  `music.gd` (per-dungeon ambience and music, menu theme).

On the pipeline side, `casc.py` and `blp.py`/`m2.py`/`wmo.py`/`db2.py` read
the WoW client; `gltf_export.py` writes the GLBs; `pipeline/d2/` holds the
MPQ, DCC, DC6 and COF decoders and every D2 export stage.

## Verification

The game takes test flags after `--`, which is how changes get checked
without playing through:

```bash
run_game.bat -- --combat-test              # scripted bow fight: kills, drops, xp
run_game.bat -- --shots=DIR --at=x,y,z     # screenshot probe at a position
run_game.bat -- --dungeon=shadowfang-keep  # jump straight into one dungeon
run_game.bat -- --menu-shot=out.png        # capture the main menu and quit
run_game.bat -- --ui-test                  # panel captures
run_game.bat -- --fps-probe                # frame timing
run_game.bat -- --walk-test                # Deadmines cove footing
run_game.bat -- --fresh                    # ignore the save
```

## Known gaps

- Waterfall doodads are static: M2 texture animation is not exported, so
  scrolling water reads as frozen.
- Bosses use the standard creature AI — no signature abilities yet.
- A few skills are spendable but inert: Inner Sight, Slow Missiles, and the
  lightning javelin line (Lightning Bolt, Lightning Strike, Lightning Fury)
  and Impale have no effect yet.
- Sixteen of the twenty dungeons are unbuilt.

## License

[PolyForm Noncommercial 1.0.0](LICENSE). Read it, run it, change it, fork
it, share it — for any noncommercial purpose. Commercial use of any kind is
not permitted, which for a Blizzard fan project is the only honest terms to
offer anyway.

No Diablo II or World of Warcraft content is in this repository or in the
binary distribution. `pipeline/` reads the player's own installs and writes
the derived assets to the player's own machine; `assets/` is git-ignored and
never shipped. Creature data comes from AzerothCore (AGPL-3.0), downloaded
from their repository at build time rather than vendored here.

Third-party components and their terms — Godot Engine (MIT), StormLib (MIT),
AzerothCore (AGPL-3.0) — are listed in [THIRD-PARTY.md](THIRD-PARTY.md).
Blizzard trademarks belong to Blizzard Entertainment; this is an unofficial,
noncommercial fan project with no affiliation or endorsement.
