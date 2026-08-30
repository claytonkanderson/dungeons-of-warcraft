"""Build every game asset from the D2 MPQs. Rerunnable; overwrites assets/."""
import export_tables
import export_amazon
import export_paperdoll
import export_monsters
import export_missiles
import export_ui

if __name__ == '__main__':
    export_tables.build()
    export_ui.build()
    export_missiles.build()
    export_amazon.build()
    export_paperdoll.build()
    export_monsters.build()
    print('ALL DONE')
