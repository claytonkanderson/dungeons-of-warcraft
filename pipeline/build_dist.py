"""Build the portable distribution into dist/DungeonsOfWarcraft.

  python pipeline/build_dist.py            # both halves
  python pipeline/build_dist.py --only exe # just the game
  python pipeline/build_dist.py --only setup   # just setup.exe

Produces the game executable (Godot release export, PCK embedded), the
frozen asset builder shipped as setup.exe, and the licence/readme files
that ship beside them. No game content of either franchise is included —
setup.exe regenerates all of it on the player's machine from their own
installs (double-click for a folder picker, or run it with --d2/--wow).

The builder is frozen in PyInstaller *onefile* mode, so the pipeline
modules cannot be found by static analysis: builder.py adds them to
sys.path at runtime. They are bundled as data instead, mirroring the
repo layout inside the extraction directory, and Pillow/numpy are
collected explicitly because only those bundled files import them.
"""
import argparse
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
OUT = ROOT / "dist" / "DungeonsOfWarcraft"

GODOT = Path(os.environ.get("DOW_GODOT", os.path.expandvars(
    r"%LOCALAPPDATA%\Microsoft\WinGet\Packages"
    r"\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe"
    r"\Godot_v4.7.2-stable_win64_console.exe")))

PRESET = "Windows"          # must match the name in game/export_presets.cfg

DOCS = [("dist-readme.txt", "README.txt"),
        ("LICENSE", "LICENSE.txt"),
        ("THIRD-PARTY.md", "THIRD-PARTY.txt")]


def run(cmd, **kw):
    print("\n$ " + " ".join(str(c) for c in cmd))
    r = subprocess.run([str(c) for c in cmd], **kw)
    if r.returncode != 0:
        sys.exit(f"failed with exit code {r.returncode}")


def check_no_asset_link():
    """A junction at game/assets would be followed into the PCK, shipping
    hundreds of megabytes of Blizzard-derived art inside the executable."""
    link = ROOT / "game" / "assets"
    if link.exists() or link.is_symlink():
        sys.exit(f"remove {link} before exporting — an asset link inside the "
                 "project directory gets baked into the PCK")


def build_exe():
    check_no_asset_link()
    if not GODOT.exists():
        sys.exit(f"Godot not found at {GODOT}; set DOW_GODOT")
    OUT.mkdir(parents=True, exist_ok=True)
    run([GODOT, "--headless", "--path", ROOT / "game",
         "--export-release", PRESET, OUT / "DungeonsOfWarcraft.exe"])


def build_builder():
    OUT.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as work:
        cmd = [sys.executable, "-m", "PyInstaller", "--onefile", "--noconfirm",
               # the player-facing name: double-click for the picker window.
               # Kept a console build (not --windowed) so build progress and
               # any early error stay visible even if the window can't open.
               "--name", "setup",
               "--distpath", OUT, "--workpath", work,
               "--specpath", work,
               # the pipeline is loaded from sys.path at runtime, so it has to
               # travel as data laid out the way builder.py expects to find it
               "--add-data", f"{HERE / 'd2'}{os.pathsep}d2",
               # only the bundled data files import these, so name them and
               # let PyInstaller's own hooks pull in what each actually needs
               "--hidden-import", "PIL.Image",
               "--hidden-import", "PIL.ImageDraw",
               "--hidden-import", "PIL.ImageFilter",
               "--hidden-import", "PIL.ImageEnhance",
               "--hidden-import", "numpy",
               # the picker GUI; tkinter's own hook pulls in the Tcl/Tk runtime
               "--hidden-import", "tkinter",
               "--hidden-import", "tkinter.filedialog",
               "--hidden-import", "tkinter.scrolledtext"]
        for py in sorted(HERE.glob("*.py")):
            if py.name in ("builder.py", "build_dist.py"):
                continue
            cmd += ["--add-data", f"{py}{os.pathsep}."]
        cmd.append(HERE / "builder.py")
        run(cmd)


def copy_docs():
    for src, dst in DOCS:
        shutil.copy(ROOT / src, OUT / dst)
        print(f"  {dst}")


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--only", choices=["exe", "setup", "docs"], default="",
                    help="build just one part (default: everything)")
    args = ap.parse_args()
    if args.only in ("", "exe"):
        build_exe()
    if args.only in ("", "setup"):
        build_builder()
    if args.only in ("", "docs"):
        print("\ndocs:")
        copy_docs()
    print(f"\ndist ready: {OUT}")
    for f in sorted(OUT.iterdir()):
        print(f"  {f.name:28} {f.stat().st_size / 1e6:8.1f} MB")


if __name__ == "__main__":
    main()
