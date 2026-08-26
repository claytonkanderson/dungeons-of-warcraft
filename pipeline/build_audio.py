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


if __name__ == "__main__":
    main()
