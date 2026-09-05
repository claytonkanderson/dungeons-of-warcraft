"""Find creature voice sets in the local WoW client by name, for the models
the dungeons use, and print a CREATURE_SFX-shaped table of what streams.

The sound tables that map a model to its kits are TACT-encrypted in this
client, so voices are found by the naming conventions WoW's creature sounds
follow: sound/creature/<family>/[m]<family><event><variant>.ogg, and for the
playable races sound/character/<race>/<sex>/<race><sex><event><variant>.ogg.

    python pipeline/probe_voices.py            # all families below
    python pipeline/probe_voices.py boar naga  # a few
    python pipeline/probe_voices.py --merge    # add what is found to voice_sets.py
"""
import pathlib
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from casc import Storage, CascError  # noqa: E402

# family -> candidate folders (under sound/creature/ unless a full path)
FAMILIES = {
    "boar": ["boar"],
    "quillboar": ["quillboar", "quilboar"],
    "crab": ["crab"],
    "hydra": ["hydra"],
    "lobstrok": ["lobstrok", "lobstrock"],
    "naga": ["naga", "nagamale"],
    "siren": ["siren", "nagafemale"],
    "threshadon": ["threshadon"],
    "troll": ["sound/character/troll/male", "sound/character/troll/trollmale"],
    "dwarf": ["sound/character/dwarf/male", "sound/character/dwarf/dwarfmale"],
    "orc_female": ["sound/character/orc/female", "sound/character/orc/orcfemale"],
    "gnome": ["sound/character/gnome/male", "sound/character/gnome/gnomemale"],
    "gnome_female": ["sound/character/gnome/female", "sound/character/gnome/gnomefemale"],
    "ogremage": ["ogremage", "ogre"],
    "troglodyte": ["troglodyte", "trogg"],
    "waterelemental": ["waterelemental", "elemental"],
    "ghost": ["ghost"],
    "lich": ["lich"],
    "hyena": ["hyena"],
    "shade": ["shade", "shadow"],
    "mechanical": ["mechanical", "gnomebot", "harvestgolem", "robot"],
    "spider": ["spider"],
    "bat": ["bat"],
}
EVENTS = {"aggro": ["aggro"], "attack": ["attack"], "wound": ["wound"],
          "death": ["death"]}
VARIANTS = ["", "a", "b", "c", "d", "e", "1", "2", "3", "01", "02", "03"]


def probe(want):
    """family -> {event: [paths]} for what actually streams."""
    s = Storage()
    out = {}
    for fam in want:
        result = {}
        for folder in FAMILIES.get(fam, [fam]):
            base = folder if "/" in folder else f"sound/creature/{folder}"
            stem = folder.split("/")[-1]
            stems = {stem}
            if "/" in folder:
                parts = folder.split("/")
                if len(parts) >= 4:
                    stems.add(parts[2] + parts[3])
            for ev, names in EVENTS.items():
                for nm in names:
                    for st in stems:
                        for pre in ("", "m"):
                            for v in VARIANTS:
                                path = f"{base}/{pre}{st}{nm}{v}.ogg"
                                fd = s.root.fdid_for_path(path)
                                if fd is None:
                                    continue
                                try:
                                    if len(s.read_fdid(fd)) < 1000:
                                        continue
                                except (CascError, KeyError):
                                    continue
                                result.setdefault(ev, [])
                                if path not in result[ev]:
                                    result[ev].append(path)
            if result:
                break
        if result:
            out[fam] = result
    return out


def merge():
    """Add newly found families to voice_sets.py (existing ones are kept)."""
    import voice_sets
    sets = dict(voice_sets.VOICE_SETS)
    found = probe([f for f in FAMILIES if f not in sets])
    sets.update(found)
    src = pathlib.Path(voice_sets.__file__).read_text(encoding="utf-8")
    head = src[:src.index("VOICE_SETS = {")]
    nl = chr(10)
    body = "VOICE_SETS = {" + nl
    for fam in sorted(sets):
        body += '    "%s": {' % fam + nl
        for ev, paths in sets[fam].items():
            body += '        "%s": [' % ev + nl
            for pth in paths:
                body += '            "%s",' % pth + nl
            body += '        ],' + nl
        body += '    },' + nl
    body += '}' + nl
    pathlib.Path(voice_sets.__file__).write_text(head + body, encoding="utf-8")
    print(f"voice_sets.py: {len(sets)} families ({len(found)} added: {sorted(found)})")


def main():
    if sys.argv[1:] == ["--merge"]:
        merge()
        return
    want = sys.argv[1:] or list(FAMILIES)
    s = Storage()
    found_total = 0
    print("VOICE_SETS_FOUND = {")
    for fam in want:
        result = {}
        for folder in FAMILIES.get(fam, [fam]):
            base = folder if "/" in folder else f"sound/creature/{folder}"
            stem = folder.split("/")[-1]
            stems = {stem}
            if "/" in folder:                # character/<race>/<sex> -> racesex
                parts = folder.split("/")
                if len(parts) >= 4:
                    stems.add(parts[2] + parts[3])
            for ev, names in EVENTS.items():
                for nm in names:
                    for st in stems:
                        for pre in ("", "m"):
                            for v in VARIANTS:
                                path = f"{base}/{pre}{st}{nm}{v}.ogg"
                                fd = s.root.fdid_for_path(path)
                                if fd is None:
                                    continue
                                try:
                                    if len(s.read_fdid(fd)) < 1000:
                                        continue
                                except (CascError, KeyError):
                                    continue
                                result.setdefault(ev, [])
                                if path not in result[ev]:
                                    result[ev].append(path)
            if result:
                break
        n = sum(len(v) for v in result.values())
        found_total += n
        if result:
            print(f'    "{fam}": {{')
            for ev, paths in result.items():
                print(f'        "{ev}": {paths!r},')
            print("    },")
        else:
            print(f"    # {fam}: nothing streams under {FAMILIES.get(fam, [fam])}")
    print("}")
    print(f"# {found_total} files", file=sys.stderr)


if __name__ == "__main__":
    main()
