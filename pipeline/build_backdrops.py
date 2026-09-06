"""Per-dungeon menu backdrops from the client's own painted dungeon art.

The official loading screens are named in the manifest but Blizzard does not
ship their content to local storage -- all 60 are missing from an otherwise
~90%-complete install -- so they are unreachable without going to the CDN.
The LFG browser's backgrounds are the same painter's work at a smaller size,
they cover every dungeon on the ladder, and they are always installed.

They are only 256x128, so this upscales and softens them and normalises every
one to the same mean brightness: the source art runs from near-black
(Stratholme) to bright teal (Deadmines), and a menu needs them to sit at a
consistent readable dimness behind text.
"""
import os

from blp import decode_blp
from config import ASSETS

SIZE = (1280, 720)
TARGET_LUMA = 32.0      # mean brightness every backdrop is pulled toward
BLUR = 1.4

# LFG art is full-bleed; the Encounter Journal buttons sit in a corner of a
# mostly transparent sheet and carry a drawn border, so those get trimmed to
# their opaque content and then inset past the border.
LFG = "interface/lfgframe/ui-lfg-background-%s.blp"
EJ = "interface/encounterjournal/ui-ej-dungeonbutton-%s.blp"
EJ_INSET = 5

ART = {
    "ragefire-chasm": ["ragefirechasm"],
    "wailing-caverns": ["wailingcaverns"],
    "deadmines": ["deadmines"],
    "shadowfang-keep": ["shadowfangkeep"],
    "blackfathom-deeps": ["blackfathomdeeps"],
    "stockade": ["thestockade", "stockade"],
    "gnomeregan": ["gnomeregan"],
    "razorfen-kraul": ["razorfenkraul"],
    "scarlet-monastery-graveyard": ["scarletmonastery"],
    "scarlet-monastery-library": ["scarletmonastery"],
    "scarlet-monastery-armory": ["scarletmonastery"],
    "scarlet-monastery-cathedral": ["scarletmonastery"],
    "razorfen-downs": ["razorfendowns"],
    "uldaman": ["uldaman"],
    "zul-farrak": ["zulfarrak"],
    "maraudon": ["maraudon"],
    "sunken-temple": ["sunkentemple", "thetempleofatalhakkar"],
    "blackrock-depths": ["blackrockdepths"],
    "lower-blackrock-spire": ["lowerblackrockspire", "blackrockspire"],
    "dire-maul": ["diremaul"],
    "scholomance": ["scholomance"],
    "stratholme": ["stratholme"],
    "upper-blackrock-spire": ["upperblackrockspire", "blackrockspire"],
}


def _readable(s, fdid):
    """In root and actually present in the local archives."""
    if not fdid:
        return False
    ckey = s.root.by_fdid.get(fdid)
    if ckey is None:
        return False
    ekey = s.encoding.get(ckey)
    return bool(ekey and s.index.get(ekey[:9]))


def _source(s, names):
    for name in names:
        for pattern in (LFG, EJ):
            fdid = s.root.fdid_for_path(pattern % name)
            if _readable(s, fdid):
                return fdid, pattern is EJ
    return None, False


def _process(img, inset):
    from PIL import Image, ImageEnhance, ImageFilter, ImageDraw
    box = img.getchannel("A").getbbox()      # the art, not the padding
    if box:
        img = img.crop(box)
    img = img.convert("RGB")
    if inset:
        img = img.crop((inset, inset, img.width - inset, img.height - inset))
    scale = max(SIZE[0] / img.width, SIZE[1] / img.height)
    img = img.resize((int(img.width * scale + 1), int(img.height * scale + 1)),
                     Image.LANCZOS)
    x = (img.width - SIZE[0]) // 2
    y = (img.height - SIZE[1]) // 2
    img = img.crop((x, y, x + SIZE[0], y + SIZE[1]))
    img = img.filter(ImageFilter.GaussianBlur(BLUR))
    grey = img.convert("L")
    mean = sum(grey.getdata()) / float(grey.width * grey.height)
    img = ImageEnhance.Brightness(img).enhance(
        min(1.6, TARGET_LUMA / max(mean, 8.0)))
    img = ImageEnhance.Color(img).enhance(0.72)
    # vignette: rim goes to near-black so the panels and text read against it
    vig = Image.new("L", SIZE, 0)
    ImageDraw.Draw(vig).ellipse(
        (-SIZE[0] * 0.30, -SIZE[1] * 0.45, SIZE[0] * 1.30, SIZE[1] * 1.45),
        fill=190)
    vig = vig.filter(ImageFilter.GaussianBlur(110))
    dark = Image.new("RGB", SIZE, (3, 2, 2))
    return Image.blend(dark, Image.composite(img, Image.blend(dark, img, 0.3), vig),
                       0.88)


def build(s, force=False):
    from PIL import Image
    outdir = os.path.join(ASSETS, "wow", "backdrops")
    os.makedirs(outdir, exist_ok=True)
    done = missing = 0
    for did, names in ART.items():
        out = os.path.join(outdir, did + ".png")
        if os.path.exists(out) and not force:
            done += 1
            continue
        fdid, is_ej = _source(s, names)
        if fdid is None:
            print("  no dungeon art for %s" % did)
            missing += 1
            continue
        w, h, rgba = decode_blp(s.read_fdid(fdid))
        img = Image.frombytes("RGBA", (w, h), rgba)
        _process(img, EJ_INSET if is_ej else 0).save(out)
        done += 1
    print("backdrops: %d dungeons, %d without art" % (done, missing))


def main():
    from casc import Storage
    build(Storage(verbose=False), force=True)


if __name__ == "__main__":
    main()
