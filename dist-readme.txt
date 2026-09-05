DUNGEONS OF WARCRAFT
a Diablo / Warcraft hybrid mod
================================

Vanilla WoW dungeons, played as a Diablo II Amazon: D2 interface, skills,
and loot; Warcraft environments, enemies, music, and sounds.

This download contains NO game assets from either title. Everything is
generated on your machine from your own installs. You need, on 64-bit
Windows with about 2 GB free (no internet connection is needed):

  1. Diablo II. Any install whose folder contains the classic archives
     d2data.mpq and patch_d2.mpq (a 1.14 install, or Diablo II with the
     original discs/installer applied). Diablo II: Resurrected does NOT
     ship these .mpq files and will not work.

  2. World of Warcraft Classic Anniversary, with its game data fully
     downloaded. In the Battle.net app this is the version on the
     "WoW Classic" product whose realm list reads "Anniversary Realms";
     its folder holds a .build.info file listing the product
     "wow_anniversary". Built and tested against 2.5.6.69546 — any 2.5.x
     Anniversary build should work; retail, Season of Discovery, Classic
     Era, and Wrath/Cata Classic are different clients and will not.

     IMPORTANT: the Anniversary client streams its data on demand, so a
     fresh or partial install can be missing files the builder needs
     (you will see "not in local storage" lines and gaps in the result).
     Before building, let Battle.net finish downloading — turn OFF any
     "play while downloading" / streaming option and wait for a full
     install.

FIRST RUN — build the assets (10-20 minutes, ~600 MB):

  Double-click setup.exe. A window opens; use its two "Browse..." buttons
  to pick Diablo II.exe and World of Warcraft Launcher.exe (each sits in
  the folder the build needs — d2data.mpq beside the first, Data and
  .build.info beside the second), then click "Build assets" and watch the
  progress. It remembers your choices for next time.

  Prefer the command line? Pass the two folders instead of using the window:

    setup.exe --d2 "C:\Path\To\Diablo II" --wow "C:\Path\To\World of Warcraft"

  Point --d2 at the folder that CONTAINS d2data.mpq, and --wow at the
  folder that CONTAINS the Data directory and .build.info (in Battle.net:
  the game tile -> the gear icon -> "Show in Explorer"). Keep the quotes;
  the paths have spaces.

  Everything Setup generates goes into a _build folder next to the
  executables: _build\assets (the game content), _build\setup.log (a full
  record of the build — send this if something goes wrong), and the paths
  you picked. It is created automatically.

  Setup looks for both games on its own (Battle.net's records, the
  registry, the usual folders) and pre-fills the paths; Browse is there
  for when it guesses wrong. Creature spawn/stat data from the open-source
  AzerothCore project (github.com/azerothcore) is included, so no download
  happens during the build. Windows SmartScreen may warn that setup.exe
  is from an unknown publisher (it is unsigned) — "More info" -> "Run
  anyway".

THEN PLAY:

  DungeonsOfWarcraft.exe

  The game opens on the dungeon ladder: create a character (a level-14
  Amazon with 14 skill points and 70 stat points to spend), pick a
  dungeon, and go. Completing a dungeon's final boss unlocks the next.

CONTROLS

  WASD + mouse        move + look          LMB / RMB   the two D2 skills
  arrow keys          look (no mouse)      K / L       same two skills (keys)
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
  MPQ Huffman tables (MIT); and the rows of AzerothCore's world database
  (AGPL-3.0) that describe these dungeons, bundled inside setup.exe.

  No Blizzard content ships in this download. Everything the game draws
  and plays is generated on your machine from your own two installs.
  This project is unofficial and is not affiliated with, endorsed by, or
  sponsored by Blizzard Entertainment.
