"""Extract the WoW soundscape for the Deadmines into assets/wow/audio.

soundkit/soundkitentry/areatable.db2 are not in the local install, so the
usual id chain is dead — but every sound file's *name hash* is in the root,
so known vanilla paths resolve directly (same trick as the baked-NPC
textures). The selection is curated: the dungeon's own ambience loop plus
the dark vanilla mood sets that fit a haunted pirate mine.

D2 sound effects (player attacks, loot, UI) stay with the Sfx autoload;
this feeds the Music autoload only.
"""
import json

from config import OUT
from casc import Storage, CascError

AMBIENCE = [
    "sound/ambience/zoneambience/deadmines.ogg",
]
# creature voices + melee foley (paths confirmed by name-hash probing;
# the soundkit db2s are absent locally so ids can't be chased)
CREATURE_SFX = {
    "peasant": {
        "aggro": ["sound/creature/peasant/peasantwarcry1.ogg",
                  "sound/creature/peasant/peasantready1.ogg"],
        "flavor": ["sound/creature/peasant/peasantyes1.ogg",
                   "sound/creature/peasant/peasantyes3.ogg",
                   "sound/creature/peasant/peasantyes4.ogg",
                   "sound/creature/peasant/peasantwhat2.ogg",
                   "sound/creature/peasant/peasantwhat3.ogg",
                   "sound/creature/peasant/peasantwhat4.ogg"],
    },
    "goblin": {
        "aggro": ["sound/creature/goblin/goblinaggroa.ogg"],
        "attack": ["sound/creature/goblin/goblinattacka.ogg",
                   "sound/creature/goblin/goblinattackb.ogg",
                   "sound/creature/goblin/goblinattackc.ogg"],
        "wound": ["sound/creature/goblin/goblinwounda.ogg",
                  "sound/creature/goblin/goblinwoundb.ogg",
                  "sound/creature/goblin/goblinwoundc.ogg"],
        "death": ["sound/creature/goblin/goblindeatha.ogg"],
    },
    "murloc": {
        "aggro": ["sound/creature/murloc/mmurlocaggroa.ogg",
                  "sound/creature/murloc/mmurlocaggrob.ogg",
                  "sound/creature/murloc/mmurlocaggroc.ogg"],
        "attack": ["sound/creature/murloc/mmurlocattacka.ogg",
                   "sound/creature/murloc/mmurlocattackb.ogg",
                   "sound/creature/murloc/mmurlocattackc.ogg"],
        "wound": ["sound/creature/murloc/mmurlocwounda.ogg",
                  "sound/creature/murloc/mmurlocwoundb.ogg",
                  "sound/creature/murloc/mmurlocwoundc.ogg"],
        "death": ["sound/creature/murloc/mmurlocdeath2a.ogg"],
    },
    "ogre": {
        "aggro": ["sound/creature/ogre/mogreaggro1.ogg",
                  "sound/creature/ogre/mogreaggro2.ogg",
                  "sound/creature/ogre/mogreaggro3.ogg"],
        "wound": ["sound/creature/ogre/mogrewound1.ogg",
                  "sound/creature/ogre/mogrewound2.ogg",
                  "sound/creature/ogre/mogrewound3.ogg"],
        "death": ["sound/creature/ogre/mogredeath1.ogg"],
    },
}
IMPACTS = {
    "sword": ["sound/item/weapons/sword1h/m1hswordhitflesh1a.ogg",
              "sound/item/weapons/sword1h/m1hswordhitflesh1b.ogg",
              "sound/item/weapons/sword1h/m1hswordhitflesh1c.ogg"],
    "heavy": ["sound/item/weapons/sword2h/m2hswordhitflesh1a.ogg",
              "sound/item/weapons/sword2h/m2hswordhitflesh1b.ogg",
              "sound/item/weapons/sword2h/m2hswordhitflesh1c.ogg",
              "sound/item/weapons/mace2h/2hmacehitflesh1a.ogg",
              "sound/item/weapons/mace2h/2hmacehitflesh1b.ogg",
              "sound/item/weapons/mace2h/2hmacehitflesh1c.ogg"],
}

MUSIC = [
    "sound/music/zonemusic/cursedland/cursedland01.mp3",
    "sound/music/zonemusic/cursedland/cursedland02.mp3",
    "sound/music/zonemusic/cursedland/cursedland03.mp3",
    "sound/music/zonemusic/cursedland/cursedland04.mp3",
    "sound/music/zonemusic/cursedland/cursedland05.mp3",
    "sound/music/zonemusic/cursedland/cursedland06.mp3",
    "sound/music/zonemusic/evilforest/dayevilforest01.mp3",
    "sound/music/zonemusic/evilforest/dayevilforest02.mp3",
    "sound/music/zonemusic/evilforest/dayevilforest03.mp3",
    "sound/music/zonemusic/evilforest/nightevilforest01.mp3",
    "sound/music/zonemusic/evilforest/nightevilforest02.mp3",
    "sound/music/zonemusic/evilforest/nightevilforest03.mp3",
]


def main():
    s = Storage()
    out_dir = OUT / "audio"
    out_dir.mkdir(parents=True, exist_ok=True)
    manifest = {"ambience": [], "music": [], "gap": [20, 60],
                "ambience_db": -8.0, "music_db": -6.0}
    for group, paths in (("ambience", AMBIENCE), ("music", MUSIC)):
        for p in paths:
            name = p.rsplit("/", 1)[-1]
            try:
                data = s.read_path(p)
            except (CascError, KeyError) as e:
                print(f"miss: {p} ({e})")
                continue
            (out_dir / name).write_bytes(data)
            manifest[group].append(name)
            print(f"{group}: {name} ({len(data)//1024} KB)")
    (out_dir / "audio.json").write_text(json.dumps(manifest, indent=1))
    print(f"wrote {out_dir / 'audio.json'}")

    # creature voices + impact foley -> wowsfx.json for the WowSfx autoload
    sfx = {"voices": {}, "impacts": {}}
    def pull(paths):
        names = []
        for p in paths:
            name = p.rsplit("/", 1)[-1]
            try:
                data = s.read_path(p)
            except (CascError, KeyError) as e:
                print(f"miss: {p} ({e})")
                continue
            (out_dir / name).write_bytes(data)
            names.append(name)
        return names

    for group, fields in CREATURE_SFX.items():
        sfx["voices"][group] = {f: pull(ps) for f, ps in fields.items()}
        print(f"voice {group}: " + ", ".join(
            f"{f} x{len(v)}" for f, v in sfx["voices"][group].items()))
    for kind, paths in IMPACTS.items():
        sfx["impacts"][kind] = pull(paths)
        print(f"impact {kind}: x{len(sfx['impacts'][kind])}")
    (out_dir / "wowsfx.json").write_text(json.dumps(sfx, indent=1))
    print(f"wrote {out_dir / 'wowsfx.json'}")


if __name__ == "__main__":
    main()
