# Developing Dungeons of Warcraft

Everything a player needs is in [README.md](README.md). This file is the
rest: building from a checkout, the asset pipeline, adding a dungeon, the
test flags, the project layout and the release build.

## Prerequisites

- **Godot 4.7.2**, exactly. The project, `run_game.bat` and the release
  script are pinned to it; `pipeline/build_dist.py` refuses any other
  version. The winget package installs it where the scripts expect
  (`%LOCALAPPDATA%\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_...`);
  set `DOW_GODOT` to point elsewhere.
- **Python 3.11+** with `pip install pillow numpy`.
- Both game installs, as described in the README.

## Building the assets

`assets/` is git-ignored and never committed: it is derived entirely from
the two installs. One command builds all of it:

```bash
python pipeline/builder.py --d2 "C:\Path\To\Diablo II" --wow "C:\Path\To\World of Warcraft"
```

Either path can be omitted; the builder finds the installs the same way
`setup.exe` does (Battle.net's product database, the registry, the usual
folders) and `--detect` prints what it found. Every run writes `setup.log`
beside the executable with the full stage-by-stage detail. A bare
double-click (no arguments) opens the setup window; any argument means a
scripted run that never opens a window.

The Diablo II stages decode the MPQ archives: game tables, interface art,
missile sprites, the Amazon animation sheets, paperdoll layers, the item
catalog and its art, uniques, sets and affixes, the stat text and bitmap
fonts, sound effects. The WoW stages open the CASC storage and build each
configured dungeon, then the menu backdrops and the soundscape.

Individual stages, for iterating on one thing:

```bash
python pipeline/build_dungeon.py --dungeon shadowfang-keep    # or --all
python pipeline/build_creatures.py --dungeon deadmines          # models + stats
python pipeline/build_creatures.py --dungeon deadmines --stats-only
python pipeline/build_backdrops.py                             # the menu backdrops
python pipeline/build_audio.py
python pipeline/d2/build_assets.py                             # every D2 stage
```

Install paths for those come from environment variables (`DOW_D2_DIR`,
`DOW_WOW_ROOT`, `DOW_ASSETS`, `DOW_AC_DIR`) with dev-machine defaults in
`pipeline/config.py` and `pipeline/d2/config.py`.

`--skip-d2` and `--skip-wow` run one half; `--only-dungeon <id>` builds one
dungeon's WoW stage.

### AzerothCore data

Creature spawns, templates, equipment, class/level stats, gameobjects and
area triggers come from nine AzerothCore world-database tables. The rows
the configured dungeons need are vendored in `pipeline/ac_data/` (about
250 KB, AGPL-3.0, produced by `pipeline/trim_ac.py`) and are what every
build reads, so a build needs no network and always sees a schema the
loaders were checked against.

`--refresh-ac` is a developer action: it downloads the full current dumps
instead. Upstream renames or drops columns now and then, and a build from
a fresh dump can fail, or read the wrong column, until the loaders are
checked again. After a refresh, or after adding a dungeon:

```bash
python pipeline/builder.py --refresh-ac --d2 ... --wow ...   # or --ac <checkout>/data/sql/base/db_world
python pipeline/trim_ac.py --ac _build/assets/_accache
```

then rebuild a dungeon from the trimmed rows and check the creature stats
it prints before committing the new files.

### Adding a dungeon

One entry in `pipeline/dungeon_config.py`: the WoW map name, the
AzerothCore map id, the target character level, the boss names, and any
door or lever rules. Then re-trim the AzerothCore rows (above), run
`build_dungeon.py --dungeon <id>`, and add the ladder entry in
`game/scripts/dungeons.gd`. The builder reports unmatched boss names and
spawn-calibration warnings; a map with several wings (Scarlet Monastery)
warns and is fine.

Creature models the local client lacks get a stand-in from
`MODEL_STANDINS` in `build_creatures.py`; the build lists any it skipped.
Creature voices are assigned per model family in `voice_sets.py`;
`probe_voices.py --merge` searches the client for new families.

## Running from a checkout

```bash
run_game.bat
```

launches Godot against the repo's `assets/`. The game takes test flags
after `--`, which is how changes get checked without playing through:

```bash
run_game.bat -- --fresh                     # ignore the save, starter kit
run_game.bat -- --dungeon=shadowfang-keep   # jump straight into one dungeon
run_game.bat -- --combat-test               # scripted bow fight: kills, drops, xp
run_game.bat -- --item-test                 # equip every property, print what it does
run_game.bat -- --loot-test                 # drop statistics per level and kind
run_game.bat -- --loot-run                  # expected loot from clearing the first four dungeons
run_game.bat -- --ui-test                   # capture the HUD and panels to shots/
run_game.bat -- --menu-shot=<abs path>.png  # capture the main menu
run_game.bat -- --shots=DIR --at=x,y,z      # screenshot probe at a position
run_game.bat -- --mob-shot=<entry>          # a creature alive, dead and gone
run_game.bat -- --what-here                 # placements enclosing the spawn
run_game.bat -- --perf-test                 # look, sprint and crowd frame times
run_game.bat -- --walk-test / --stair-test  # footing probes
```

Two launchers keep automated runs off the desktop so they never steal
focus from whatever else is running: `capture.bat` creates the window
minimized, unfocusable and off-screen (for captures and diagnostics, which
force their own draws), and `offdesk.bat` does the same without minimizing
(for anything that must render real frames: the combat test and the perf
probe; `perf.bat` is that plus `--perf-test`). Both take the same
arguments as `run_game.bat`.

## Project layout

The Godot project builds its scenes in code; the `.tscn` files are stubs
and there are no imported resources. Assets load from the filesystem at
runtime through `Paths.root()`, which is `../assets` in the editor and
`_build/assets` beside the executable in a release.

- `world.gd` — the main scene: placements, terrain, creatures,
  gameobjects; combat resolution (collision-based arrows and thrown
  javelins, melee cleave scaled to weapon size, skill areas, enemy
  missiles), loot, doors and levers, every diagnostic.
- `wow_creature.gd` — a WoW creature: GLB visual plus AnimationPlayer, a
  state machine over D2 stats, per-element resistances, LOS-gated aggro,
  regeneration, corpse timeout, and a dormancy LOD for distant idle
  creatures.
- `player.gd` — movement, warp-based mouse look, attack timing, blocking,
  hit recovery.
- `game_state.gd` — characters, equipment and every item property's
  effect, set bonuses, stats, versioned saves.
- `item_db.gd`, `item_gen.gd` — D2 treasure classes and the quality roll;
  `item_text.gd`, `item_tooltip.gd` — the tooltip text and which lines the
  game acts on (the rest are dimmed).
- `d2_panel.gd`, `d2_field.gd`, `d2_font.gd` — a D2 page composed at its
  native 320×432 and scaled once; text fields; the bitmap fonts, each
  drawn only at its own pixel size.
- `hud.gd`, `char_sheet.gd`, `inventory_ui.gd`, `skill_tree_ui.gd`,
  `main_menu.gd`, `menu_ui.gd`, `paperdoll.gd` — the interface.
- `sfx.gd` (D2 effects), `wow_sfx.gd` (creature voices, impacts),
  `music.gd` (ambience and music).

On the pipeline side, `casc.py` and `blp.py`/`m2.py`/`wmo.py`/`db2.py` read
the WoW client; `gltf_export.py` writes the GLBs (including baking M2
batch visibility into bone scale); `pipeline/d2/` holds the MPQ, DCC, DC6
and COF decoders and every D2 export stage.

## Saves

Saves are JSON, one per character, and carry a `version` field
(`GameState.SAVE_VERSION`). A layout change that defaults cannot absorb
gets a step in `_migrate_save`, which upgrades one version at a time.
Files without the field are version 0.

## Release build

```bash
python pipeline/build_dist.py
```

exports the game with Godot 4.7.2, freezes the pipeline into `setup.exe`
with the vendored AzerothCore rows, and writes the player README
(`dist-readme.txt` becomes `README.txt`), the licence and the third-party
notice into `dist/DungeonsOfWarcraft/`. Neither executable is code-signed,
so SmartScreen warns on first run.

`README.md` is the repository's front page on GitHub; `dist-readme.txt` is
the plain-text README that ships in the zip for players who never see
GitHub. They cover the same ground and should be kept in step.

## Known gaps

- Waterfall doodads are static: M2 texture animation is not exported.
- Bosses have no signature abilities.
- Item lines the game does not act on yet are dimmed in the tooltip:
  chance-to-cast procs, charges, durability and repair, sockets, and the
  other classes' skill bonuses.
- The Shadowfang Keep entrance-stair probe regressed (0.24 m climbed against
  a 3.7 m baseline) on both physics engines; not yet diagnosed.
- Ten of the twenty dungeons are unbuilt.
