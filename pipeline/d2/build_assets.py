"""Build every D2-side asset from the Diablo II MPQs. Rerunnable; overwrites
assets/.

The same stage list builder.py runs for its D2 half — keep the two in step.
This used to stop after the sprite stages, which left the game with no item
catalog, no uniques or sets, no stat text or font, and no sound effects.
"""
import os
import sys

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

# export_setbonus lives one level up, beside the WoW pipeline
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import export_setbonus  # noqa: E402


def build():
    export_tables.build()
    export_ui.build()
    export_missiles.build()
    export_amazon.build()
    export_paperdoll.build()
    export_monsters.ROSTER = {"VK": "valkyrie"}
    export_monsters.build()
    export_items.build()
    export_affixes.build()
    export_statdisplay.export_font("font16")
    export_statdisplay.export_statdisplay()
    export_sounds.build()
    export_setbonus.main()


if __name__ == '__main__':
    build()
    print('ALL DONE')
