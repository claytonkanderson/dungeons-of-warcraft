"""Prove the self-update against the published release.

  python pipeline/test_update.py             # stage and launch
  python pipeline/test_update.py --no-launch # stage only

Exports a throwaway game executable stamped one patch version below the
checkout's, puts it in dist/updtest beside the current setup.exe with the
checkout's assets linked in (so no rebuild is triggered), and starts it.
At the menu the game should say "Updating to <version>: downloading",
restart, and come back as the released build: the script waits, then
compares the folder's executable with dist/DungeonsOfWarcraft/'s. The
checkout's version.gd is restored either way.

Needs a release newer than the throwaway's version on GitHub (the current
one published with build_dist.py --publish), and dist/DungeonsOfWarcraft
built with the current version.
"""
import argparse
import hashlib
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
DIST = ROOT / "dist" / "DungeonsOfWarcraft"
TEST = ROOT / "dist" / "updtest"
VERSION_GD = ROOT / "game" / "scripts" / "version.gd"


def md5(p):
    return hashlib.md5(p.read_bytes()).hexdigest()[:12]


def export():
    """The game executable into dist/, the export's own output kept for
    the error (a game running from dist/ locks the file, for one)."""
    r = subprocess.run([sys.executable, str(HERE / "build_dist.py"), "--only", "exe",
                        "--no-zip"], capture_output=True, text=True)
    if r.returncode != 0:
        print(r.stdout[-3000:])
        print(r.stderr[-3000:])
        sys.exit("the export failed (see above). Is DungeonsOfWarcraft.exe running "
                 f"from {DIST}? Close it and retry.")


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--no-launch", action="store_true", help="stage the folder only")
    args = ap.parse_args()
    src = VERSION_GD.read_text()
    m = re.search(r'VERSION := "(\d+)\.(\d+)\.(\d+)"', src)
    if not m:
        sys.exit("version.gd has no VERSION")
    cur = ".".join(m.groups())
    major, minor, patch = (int(x) for x in m.groups())
    # one step below, borrowing from the minor or major at a zero
    if patch > 0:
        lower = f"{major}.{minor}.{patch - 1}"
    elif minor > 0:
        lower = f"{major}.{minor - 1}.9"
    elif major > 0:
        lower = f"{major - 1}.9.9"
    else:
        sys.exit("0.0.0 has nothing below it; bump the version first")
    if not (DIST / "DungeonsOfWarcraft.exe").exists() or not (DIST / "setup.exe").exists():
        sys.exit(f"build the release first: {DIST} is missing the executables")
    released = md5(DIST / "DungeonsOfWarcraft.exe")

    # the throwaway: the same checkout, one version lower
    print(f"exporting a throwaway executable at {lower} (the release is {cur})")
    VERSION_GD.write_text(src.replace(f'VERSION := "{cur}"', f'VERSION := "{lower}"'))
    try:
        export()
        if TEST.exists():
            shutil.rmtree(TEST)
        (TEST / "_build").mkdir(parents=True)
        shutil.copy(DIST / "DungeonsOfWarcraft.exe", TEST / "DungeonsOfWarcraft.exe")
        shutil.copy(DIST / "setup.exe", TEST / "setup.exe")
        subprocess.run(["cmd", "/c", "mklink", "/J", str(TEST / "_build" / "assets"),
                        str(ROOT / "assets")], check=True, capture_output=True)
    finally:
        # the checkout keeps its version, and dist/ its release build
        VERSION_GD.write_text(src)
        export()
    old = md5(TEST / "DungeonsOfWarcraft.exe")
    print(f"staged {TEST}: executable {old} ({lower}); the release build is {released} ({cur})")
    if args.no_launch:
        print("launch dist/updtest/DungeonsOfWarcraft.exe and watch the menu's bottom line")
        return

    print("launching; the menu should say 'Updating to %s: downloading', then restart" % cur)
    subprocess.Popen([str(TEST / "DungeonsOfWarcraft.exe")], cwd=str(TEST))
    for i in range(24):
        time.sleep(5)
        now = md5(TEST / "DungeonsOfWarcraft.exe")
        if now == released:
            print(f"after {5 * (i + 1)} s the folder's executable is the release build: "
                  f"the update applied and the game restarted itself")
            print("close that game window when you are done; dist/updtest can be deleted")
            return
    print("the executable did not change in two minutes: check the menu's bottom line "
          "and %APPDATA%\\Godot\\app_userdata\\Dungeons of Warcraft\\logs\\godot.log")


if __name__ == "__main__":
    main()
