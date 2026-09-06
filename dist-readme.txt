DUNGEONS OF WARCRAFT
Diablo II x World of Warcraft - a loot-frenzy FPS
=================================================

(This is the README that ships with the download. The project page,
with screenshots, a gameplay video and the source, is at
https://github.com/claytonkanderson/dungeons-of-warcraft)

Vanilla WoW dungeons, walked in first person as a Diablo II Amazon:
Diablo's interface, skills, stats and loot; Warcraft's environments,
enemies, music and sounds. A non-commercial fan project.

This download contains NO game assets from either title. Everything is
generated on your machine from your own installs. You need, on 64-bit
Windows with about 2 GB free (no internet connection is needed):

  1. Diablo II: Lord of Destruction - the 2000-2001 game at patch 1.13
     or 1.14, NOT Diablo II: Resurrected. Its folder contains d2data.mpq
     and patch_d2.mpq; Resurrected does not ship those archives and will
     not work. Blizzard still sells it (us.shop.battle.net, "Diablo II:
     Lord of Destruction"); if you already own it, the installer is at
     us.support.blizzard.com/en/help/article/13867. Original discs work
     too.

  2. World of Warcraft Classic Anniversary, with its game data fully
     downloaded. In the Battle.net app this is the "WoW Classic" product
     whose realm list reads "Anniversary Realms"; its folder holds a
     .build.info file naming the product "wow_anniversary". Built and
     tested against 2.5.6.69546; any 2.5.x Anniversary build should work.
     Retail, Season of Discovery, Classic Era and Wrath/Cata Classic are
     different clients and will not.

     IMPORTANT: the Anniversary client streams its data on demand, so a
     fresh or partial install can be missing files the builder needs.
     Before building, turn OFF "play while downloading" in Battle.net and
     wait for the full install.

FIRST RUN - build the assets (5-10 minutes, ~600 MB):

  Double-click setup.exe. It looks for both games on its own and fills in
  the two paths; if one is empty or wrong, use Browse to pick
  Diablo II.exe and World of Warcraft Launcher.exe. Click "Build assets"
  and wait for the progress bar to fill. It remembers your choices.

  Windows SmartScreen may warn that setup.exe is from an unknown
  publisher (it is unsigned): "More info" -> "Run anyway".

  Prefer the command line? Pass the two folders instead:

    setup.exe --d2 "C:\Path\To\Diablo II" --wow "C:\Path\To\World of Warcraft"

  Point --d2 at the folder that CONTAINS d2data.mpq, and --wow at the
  folder that CONTAINS the Data directory and .build.info (in Battle.net:
  the game tile -> the gear icon -> "Show in Explorer"). Keep the quotes.

  Everything Setup generates goes into a _build folder next to the
  executables: _build\assets (the game content), _build\setup.log (the
  full record of the build - send this if something goes wrong), and the
  paths you picked.

THEN PLAY:

  DungeonsOfWarcraft.exe

  Create a character (a level-1 Amazon with an experience charm and a
  javelin in her pack), pick Ragefire Chasm, and go. Killing a dungeon's
  final boss unlocks the next one on the ladder.

CONTROLS

  WASD + mouse        move + look          LMB / RMB   the two Diablo skills
  arrow keys          look (no mouse)      K / L       same two skills (keys)
  Shift               run (stamina)        Space       jump
  T                   skill tree (click +1, ctrl+click bind LMB,
                      right-click bind RMB, hover + F1-F5 bind hotkey)
  I / C               inventory / character sheet
  E                   interact / pick up   Alt         loot labels
  1-4                 belt potions         F1-F5       swap RMB skill
  F9                  manual save          F11         fullscreen
  Esc                 menu / close panels

CURRENT LIMITATIONS

  - Amazon only.
  - Ten of the twenty dungeons are built: Ragefire Chasm, Wailing
    Caverns (good luck - there's no map), The Deadmines, Shadowfang Keep,
    Blackfathom Deeps, The Stockade, Gnomeregan, Razorfen Kraul, Scarlet
    Monastery (all four wings) and Razorfen Downs. The rest are listed and
    arrive as they get built.
  - Windows only, keyboard and mouse only (no controller support).

NOTES

  - Your characters live in %APPDATA%\Godot\app_userdata\Dungeons of
    Warcraft\characters\ - one file each, safe to back up.
  - Diablo II and World of Warcraft are trademarks of Blizzard
    Entertainment; this mod is unplayable without owning both.

LICENSE

  Dungeons of Warcraft is released under the PolyForm Noncommercial
  License 1.0.0 - see LICENSE.txt. You may use, modify, fork and share
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
