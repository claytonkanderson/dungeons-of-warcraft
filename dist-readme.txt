DUNGEONS OF WARCRAFT
a Diablo / Warcraft hybrid mod
================================

Vanilla WoW dungeons, played as a Diablo II Amazon: D2 interface, skills,
and loot; Warcraft environments, enemies, music, and sounds.

This download contains NO game assets from either title. Everything is
generated on your machine from your own installs. You need:

  1. Diablo II installed (1.14, or any install with the classic .mpq
     files in its folder)
  2. World of Warcraft Classic Anniversary installed (with its game
     data downloaded)

FIRST RUN — build the assets (5-15 minutes, ~400 MB):

  builder.exe --d2 "C:\Path\To\Diablo II" --wow "C:\Path\To\World of Warcraft"

  Creature spawn/stat data is fetched from the open-source AzerothCore
  project (github.com/azerothcore) during the build.

THEN PLAY:

  DungeonsOfWarcraft.exe

  The game opens on the dungeon ladder: create a character (a level-14
  Amazon with 14 skill points and 70 stat points to spend), pick a
  dungeon, and go. Completing a dungeon's final boss unlocks the next.

CONTROLS

  WASD + mouse        move + look          LMB / RMB   the two D2 skills
  Shift               run (stamina)        Space       jump
  T                   skill tree (click +1, ctrl+click bind LMB,
                      right-click bind RMB, hover + F1-F5 bind hotkey)
  I / C               inventory / character sheet
  E                   pick up nearest      Alt         loot labels
  1-4                 belt potions         F1-F5       swap RMB skill
  F9                  manual save          Esc         menu / close panels

NOTES

  - Your characters live in %APPDATA%\Godot\app_userdata\Dungeons of
    Warcraft\characters\ — one file each, safe to back up.
  - Built dungeons so far: Ragefire Chasm, Wailing Caverns, The
    Deadmines, Shadowfang Keep. The rest of the ladder is listed and
    arrives as it gets built.
  - This is a non-commercial fan project. Diablo II and World of
    Warcraft are trademarks of Blizzard Entertainment; this mod is
    unplayable without owning both.

LICENSE

  Dungeons of Warcraft is released under the PolyForm Noncommercial
  License 1.0.0 — see LICENSE.txt. You may use, modify, fork and share
  it for any noncommercial purpose; commercial use is not permitted.

  Required Notice: Copyright 2026 Clayton Anderson

  THIRD-PARTY.txt lists the components that keep their own terms: the
  Godot Engine (MIT), compiled into DungeonsOfWarcraft.exe; StormLib's
  MPQ Huffman tables (MIT); and AzerothCore's world database
  (AGPL-3.0), which builder.exe downloads to your machine at build time
  rather than bundling.

  No Blizzard content ships in this download. Everything the game draws
  and plays is generated on your machine from your own two installs.
  This project is unofficial and is not affiliated with, endorsed by, or
  sponsored by Blizzard Entertainment.
