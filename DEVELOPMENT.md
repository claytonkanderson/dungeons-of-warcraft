# Developing Dungeons of Warcraft

Everything a player needs is in [README.md](README.md). This file is the
rest: building from a checkout, the asset pipeline, adding a dungeon, the
test flags, the project layout and the release build.

## Prerequisites

On a fresh Windows machine, `setup-dev.ps1` does all of this: it installs
Godot 4.7.2 through winget, the Python packages, checks for both game
installs and builds the assets.

```powershell
powershell -ExecutionPolicy Bypass -File setup-dev.ps1
```

By hand:

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
spawn-calibration warnings.

A map that holds several instances as separate buildings (Scarlet
Monastery) is one config entry per wing, each naming its entrance trigger
with `wing="Graveyard"` and so on. The build keeps the building on that
entrance's side of the map, and the spawns, gameobjects, props and
terrain tiles nearest it; the calibration hit rate should be near 100%
for every wing. `xp_span` sets how many levels a clear is worth (five by
default) so the wings together budget one dungeon's worth.

When one building holds several instances (Dire Maul's three wings, the
two Blackrock Spires) there is no placement to pick: `bounds` names the
part of the map in server coordinates (`xmin`/`xmax`/`ymin`/`ymax`/`zmin`/
`zmax`, any subset) whose spawns and gameobjects belong to the instance,
and `entrance` names the trigger to start at when the map's first row is
not it.

A boss a WoW script summons rather than spawns (Ragnaros, Majordomo,
Nefarian) has no creature row: `extra_spawns` lists `(name, x, y, z, o)`
in server coordinates and the build places it like any spawn; the trimmer
vendors its template and model rows by name. The positions come from
AzerothCore's boss scripts.

Creature models the local client lacks get a stand-in: the Anniversary
client streams creature models on demand and is missing the whole Scourge
line (ghoul, zombie, skeleton, abomination, the Forsaken character model)
and the slimes, 23 models in all. `MODEL_STANDINS_BY_FDID` in
`build_creatures.py` maps each missing model file id to a local model
that reads alike and whose textures are local too (ghoul to Wight, zombie
to Lost One, skeleton to Deathguard, abomination to Flesh Giant, slime to
Lesser Slime); the stand-in borrows a display row's skin for that model
and is scaled to the missing model's bounding height. A template whose
display ids the client's tables lack altogether gets one by name from
`NO_DISPLAY_STANDINS`; the older `MODEL_STANDINS` name table is the last
resort. The build lists every stand-in and anything it still skipped.

Gameobject spawns with a negative respawn time are script-raised event
props (Ragnaros' lava steam and splash, the Firelord's cache) and are left
out; WMO liquid surfaces carry the client's tiling water, lava and slime
textures (`LIQUID_TEXTURES` in `wmo_export.py`).
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
run_game.bat -- --skill-tips                # every skill's tooltip numbers at levels 1, 10, 20
run_game.bat -- --loot-test                 # drop statistics per level and kind
run_game.bat -- --loot-run                  # expected loot from clearing the first four dungeons
run_game.bat -- --ui-test                   # capture the HUD and panels to shots/
run_game.bat -- --menu-shot=<abs path>.png  # capture the main menu
run_game.bat -- --shots=DIR --at=x,y,z      # screenshot probe at a position (four compass angles)
run_game.bat -- --shots=DIR --at=x,y,z --look=yaw,pitch   # one shot from a session log's pose
run_game.bat -- --mob-shot=<entry>          # a creature alive, dead and gone
run_game.bat -- --mob-shot=<entry> --mob-dist=20 --mob-pitch=0.3   # from farther back, looking up
run_game.bat -- --what-here                 # placements enclosing the spawn
run_game.bat -- --perf-test                 # look, sprint and crowd frame times
run_game.bat -- --walk-test / --stair-test  # footing probes
run_game.bat -- --topdown=<abs path>.png   # a view straight down on the whole dungeon
run_game.bat -- --tour=90                   # a recorded survey glide (python tour_videos.py renders one per dungeon)
run_game.bat -- --replay-test               # a scripted session, recorded (see below)
run_game.bat -- --replay=<log> --no-record  # play a session log back
```

Two launchers keep automated runs off the desktop so they never steal
focus from whatever else is running: `capture.bat` creates the window
minimized, unfocusable and off-screen (for captures and diagnostics, which
force their own draws), and `offdesk.bat` does the same without minimizing
(for anything that must render real frames: the combat test and the perf
probe; `perf.bat` is that plus `--perf-test`). Both take the same
arguments as `run_game.bat`.

## Recording and replaying a session

`run_game.bat` records every session (it passes `--record`); players are
never recorded unless `"record_sessions": true` is put in their
`settings.json` (there is no menu for it), and `--no-record` wins over
both (the capture launchers pass it). Logs go to
`%APPDATA%\Godot\app_userdata\Dungeons of Warcraft\sessions\<stamp>-<character>-<dungeon>.jsonl`,
roughly half a megabyte a minute, and render to video offline:

```bash
render_replay.bat "<path to session.jsonl>" [out.mp4]
```

The log is a state log, not an input log. `replay.gd` (autoloaded as
`Replay`) runs after every gameplay node each physics tick and writes what
changed: the player's position and look angles every tick; the HUD
numbers, the creatures (position, yaw, animation clip, life), every
`BillboardAnim` under the world (arrows, enemy missiles, bolts, summons),
the items on the floor and the doors every third tick; the panels and a
full character snapshot whenever a panel opens or closes; and events for
sounds, HUD flashes and area text, which `Sfx`, `WowSfx` and `HUD` log at
their entry points.

Playback is puppetry. The world builds its geometry as usual, then
`Replay.arm` switches the world, the player and every creature to
`puppet`, turns off `GameState`'s tick, and from then on places everything
from the log, interpolating positions between samples. Nothing is
simulated, so a replay cannot drift and gameplay code owes it nothing
beyond what is logged. Anything new that should appear in a video (a new
effect type, a new HUD element) needs a line in the sampler or an event.

`--replay-test` records a scripted session (a walk, a sprint, jumps, a
fight, a potion, the inventory opened and closed); rendering the log it
prints exercises every kind of line. The render runs the game under
Godot's Movie Maker (`--write-movie`, `--fixed-fps 60`), one frame per
tick, into an MJPEG AVI with audio, then transcodes to MP4 with ffmpeg
(`winget install Gyan.FFmpeg`; the script also finds a winget install the
shell has not picked up). Movie Maker draws and encodes every frame, so
it runs at roughly real time; the window is moved off the desktop and out
of the focus order while it does.

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
- `replay.gd` — session recording as a state log, and playback as
  puppetry (above).
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
- Creature models the Anniversary client lacks now all have stand-ins;
  only trigger creatures (invisible stalkers) are skipped.
- Zul'Farrak is the first outdoor instance: spawn calibration finds no
  building to match against (0 of 271, expected), the map places fine, but
  the flat indoor ambient lighting washes out the desert; an outdoor sky
  and sun for it is still to do.
