# Amazon Deadmines

World of Warcraft's Deadmines dungeon crossed with Diablo 2's Amazon, in
Godot 4.7:

- **Environment**: the real Deadmines instance — WMOs, 850+ doodads/props,
  the cove terrain/ocean/waterfalls — extracted from a local WoW
  anniversary (2.5.5) install via the pure-Python CASC pipeline forked from
  `D:\tree\warcraft-art`.
- **UI**: Diablo 2's control panel, orbs, inventory, character sheet,
  skill tree, tooltips, and font16, from the `D:\tree\D2_Billboard`
  prototype (art decoded from a local modded D2 install).
- **Class & abilities**: the D2 Amazon — bow/melee weapon classes, the
  full skill roster, passives, D2 combat math, stats and leveling.
- **Enemies**: all 213 AzerothCore creature spawns as 3D animated WoW
  models (23 uniques, Rhahk'Zor through VanCleef) with a chase/attack AI;
  stats derived from `creature_template` + `creature_classlevelstats`.
- **Loot**: D2 drop generation — treasure classes, uniques/sets/rares/
  magic with authentic tooltip text; every kill drops quality, bosses
  shower it.

## Run

```
run_game.bat                      # normal play
run_game.bat -- --fresh           # ignore the save
run_game.bat -- --combat-test     # scripted bow-fight verification
run_game.bat -- --shots=DIR --at=x,y,z    # screenshot probe
```

Controls: WASD + mouse (warp-look — never MOUSE_MODE_CAPTURED on this
machine), Shift run, LMB/RMB = D2 action slots, T skill tree (ctrl/right
click assigns slots), I inventory, C char sheet, E pickup, Alt loot
labels, 1-4 belt potions, F1-F5 skill hotkeys (bind by hovering a learned skill in
the tree and pressing the key), F9 save, Esc frees the mouse.

## Rebuild assets (git-ignored, ~150 MB)

Everything under `assets/` regenerates from the user's own game installs;
nothing is committed.

1. D2 side: copy `amazon/ ui/ items/ missiles/ sounds/ monsters/valkyrie/
   gamedata.json` from `D:\tree\D2_Billboard\assets` (or re-run that
   repo's pipeline).
2. WoW world: copy `assets/out/deadmines` from `D:\tree\warcraft-art`
   into `assets/wow/deadmines`, or re-run `pipeline/extract_deadmines.py`
   + `build_placements.py` here.
3. `python pipeline/build_dungeon.py --dungeon <id>` builds any configured
   dungeon end to end (WMOs, placements, creatures, terrain, ambience);
   `--all` batches every entry in pipeline/dungeon_config.py.
4. `python pipeline/build_creatures.py --dungeon <id>` — 23 creature GLBs with the
   gameplay animation set + `creatures.json` stats (`--stats-only` to
   retune without re-exporting).
5. `python pipeline/build_terrain.py` — 36 ADT tiles baked to GLBs
   (splat textures, MCNR shading, MH2O ocean mesh). Needs numpy.
6. `python pipeline/build_audio.py` — WoW ambience/music via name-hash
   lookup (soundkit db2s are absent locally; paths are the trick).

Paths (WoW install, AzerothCore SQL dump) live in `pipeline/config.py`.

## Architecture

- `game/scripts/world.gd` — main scene: loads placements/terrain, spawns
  player + creatures, owns combat resolution (arrows, melee, skill AoE,
  enemy missiles), loot drops, pickups, UI wiring, save timer.
- `game/scripts/wow_creature.gd` — WoW creature: GLB visual +
  AnimationPlayer, D2-stat state machine (IDLE/CHASE/ATTACK/HURT/DEAD),
  LOS-gated aggro, caster archetype fires D2 billboard bolts.
- `game/scripts/player.gd`, `game_state.gd`, `item_*.gd`, `hud.gd`,
  `inventory_ui.gd`, `char_sheet.gd`, `skill_tree_ui.gd`, `sfx.gd` —
  ported from D2_Billboard (see its HANDOFF.md for the gotchas; they all
  apply here).
- `game/scripts/music.gd` — WoW ambience loop + shuffled music with
  silence gaps; D2 sfx stay in `sfx.gd`.
- Assets load at runtime from `res://../assets` by filesystem path — the
  project has no imported resources, so an exported PCK would not find
  them (same trade-off as both parent repos).

## Known gaps

- Waterfall doodads render as static translucent cones (texture
  animation isn't exported) — reads as icicles.
- No WMO interior water (MLIQ), no gameobjects (doors, cannon), no
  boss signature abilities (standard archetype AI by design, v1).
- Live audio is silent on this machine (WASAPI init fails → dummy
  driver); Movie Maker recordings carry the full mix.
- WoW creature voices/impacts not extracted; combat feedback is D2 sfx.
