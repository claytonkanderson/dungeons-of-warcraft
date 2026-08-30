# Third-party notices

Dungeons of Warcraft itself is licensed under the PolyForm Noncommercial
License 1.0.0 (see [LICENSE](LICENSE)). The components below are other
people's work and keep their own terms.

Nothing in this repository, and nothing in the binary distribution, contains
game content from Diablo II or World of Warcraft. Every art, audio and data
asset is generated on the player's own machine, from the player's own
installs, by `pipeline/builder.py`. The mod does not run without both games
already installed.


## Godot Engine — MIT

Redistributed: the engine runtime is compiled into `DungeonsOfWarcraft.exe`.

<https://godotengine.org> · <https://godotengine.org/license>

> Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md).
> Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.
>
> Permission is hereby granted, free of charge, to any person obtaining a copy
> of this software and associated documentation files (the "Software"), to deal
> in the Software without restriction, including without limitation the rights
> to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
> copies of the Software, and to permit persons to whom the Software is
> furnished to do so, subject to the following conditions:
>
> The above copyright notice and this permission notice shall be included in all
> copies or substantial portions of the Software.
>
> THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
> IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
> FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
> AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
> LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
> OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
> SOFTWARE.

Godot bundles further third-party libraries under their own permissive
licenses; the complete set of notices ships with the engine and is published
at the license URL above.


## StormLib — MIT

Redistributed: the MPQ Huffman byte-weight tables in
`pipeline/d2/tools/huff_tables.py` are the data tables from StormLib's
`huff.cpp`. The decompression code around them is an independent
implementation.

<https://github.com/ladislav-zezula/StormLib>

> The MIT License (MIT)
>
> Copyright (c) 1999-2013 Ladislav Zezula
>
> Permission is hereby granted, free of charge, to any person obtaining a copy
> of this software and associated documentation files (the "Software"), to deal
> in the Software without restriction, including without limitation the rights
> to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
> copies of the Software, and to permit persons to whom the Software is
> furnished to do so, subject to the following conditions:
>
> The above copyright notice and this permission notice shall be included in all
> copies or substantial portions of the Software.
>
> THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
> IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
> FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
> AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
> LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
> OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
> SOFTWARE.


## AzerothCore — AGPL-3.0

**Not redistributed.** Creature spawns, creature templates, class/level
stats and area triggers come from AzerothCore's world database. The builder
downloads those seven `.sql` files from AzerothCore's own repository onto the
player's machine at build time (`ensure_ac()` in `pipeline/builder.py`); they
are neither committed here nor bundled into any executable, and the parsers
that read them are original code.

<https://github.com/azerothcore/azerothcore-wotlk> · AGPL-3.0


## Diablo II and World of Warcraft — Blizzard Entertainment

**Not redistributed.** No Blizzard art, audio, text or data is included in
this repository or in the binary distribution. The pipeline reads the
player's own installed copies of both games and writes the derived assets to
the player's own machine.

Diablo, Diablo II, Warcraft, World of Warcraft, and Blizzard Entertainment
are trademarks or registered trademarks of Blizzard Entertainment, Inc., in
the U.S. and/or other countries. This is an unofficial, noncommercial fan
project. It is not affiliated with, endorsed by, or sponsored by Blizzard
Entertainment.
