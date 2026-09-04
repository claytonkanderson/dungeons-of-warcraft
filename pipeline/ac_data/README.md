# AzerothCore world-database rows

These nine `.sql` files are trimmed copies of tables from the
[AzerothCore](https://github.com/azerothcore/azerothcore-wotlk) world
database (`data/sql/base/db_world/`), reduced to the rows that describe the
dungeons configured in `pipeline/dungeon_config.py`: the creature spawns on
those instance maps, the templates, models and equipment of the creatures
spawned there, the items that equipment names, the gameobjects placed there
and their templates, plus the small class/level-stats and area-trigger
lookup tables in full. Nothing is modified apart from the trimming; each
file keeps its original `CREATE TABLE` header.

Copyright (C) AzerothCore and contributors. Licensed under the GNU Affero
General Public License, version 3.0 — <https://www.gnu.org/licenses/agpl-3.0.html>.
This notice and that licence apply to the files in this directory. The rest
of Dungeons of Warcraft is licensed separately (see the repository LICENSE).

Regenerate after adding a dungeon, or to pick up upstream changes:

    python pipeline/builder.py --refresh-ac --d2 ... --wow ...   # or point --ac at a checkout
    python pipeline/trim_ac.py --ac _build/assets/_accache
