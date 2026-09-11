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

GODOT_VERSION = "4.7.2"     # the engine the project is pinned to
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
    # the shipped game is built with the engine the project was tested on;
    # a different minor version imports the scenes differently enough to
    # be a release of its own
    got = subprocess.run([str(GODOT), "--version"], capture_output=True,
                         text=True).stdout.strip().splitlines()
    got = got[-1] if got else ""
    if not got.startswith(GODOT_VERSION):
        sys.exit(f"Godot {GODOT_VERSION} is required, found {got!r} at "
                 f"{GODOT}; set DOW_GODOT to a {GODOT_VERSION} build")
    OUT.mkdir(parents=True, exist_ok=True)
    run([GODOT, "--headless", "--path", ROOT / "game",
         "--export-release", PRESET, OUT / "DungeonsOfWarcraft.exe"])


def build_builder():
    OUT.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as work:
        cmd = [sys.executable, "-m", "PyInstaller", "--onefile", "--noconfirm",
               # the player-facing name: double-click for the setup window.
               # A windowed build, so no console pops up beside it; a run
               # from a terminal attaches to that terminal instead (see
               # attach_console in builder.py) and the log file has the rest.
               "--name", "setup", "--windowed",
               "--distpath", OUT, "--workpath", work,
               "--specpath", work,
               # the pipeline is loaded from sys.path at runtime, so it has to
               # travel as data laid out the way builder.py expects to find it
               "--add-data", f"{HERE / 'd2'}{os.pathsep}d2",
               # the trimmed AzerothCore dumps (pipeline/trim_ac.py): the
               # build reads these, so no download is needed at install time
               "--add-data", f"{HERE / 'ac_data'}{os.pathsep}ac_data",
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
               "--hidden-import", "tkinter.ttk"]
        for py in sorted(HERE.glob("*.py")):
            if py.name in ("builder.py", "build_dist.py"):
                continue
            cmd += ["--add-data", f"{py}{os.pathsep}."]
        cmd.append(HERE / "builder.py")
        run(cmd)


def game_version():
    import re
    src = (ROOT / "game" / "scripts" / "version.gd").read_text()
    return re.search(r'VERSION := "([^"]+)"', src).group(1)


def write_asset_versions():
    """game/scripts/asset_versions.gd from pipeline/versions.py, so the
    game knows which asset stages this build expects."""
    sys.path.insert(0, str(HERE))
    import versions
    lines = ["class_name AssetVersions",
             "## Generated by pipeline/build_dist.py from pipeline/versions.py: the asset",
             "## stages this build of the game expects, by version. The updater compares",
             "## them with _build/assets/build_manifest.json and has setup.exe redo the",
             "## stages that moved. Edit versions.py, not this file.",
             "", "const STAGES := {"]
    for k in versions.ORDER:
        lines.append(f'\t"{k}": {versions.STAGES[k]},')
    lines += ["}", ""]
    (ROOT / "game" / "scripts" / "asset_versions.gd").write_text("\n".join(lines))
    print(f"asset_versions.gd: {len(versions.STAGES)} stages")


def stamp_export_version(version):
    """The export preset's product version, shown in the exe's properties."""
    p = ROOT / "game" / "export_presets.cfg"
    s = p.read_text()
    import re
    s = re.sub(r'application/product_version="[^"]*"',
               f'application/product_version="{version}"', s)
    s = re.sub(r'application/file_version="[^"]*"',
               f'application/file_version="{version}.0"', s)
    p.write_text(s)


def publish(zip_path, version):
    """A GitHub release v<version> carrying the zip, through the gh CLI;
    the game's updater reads the latest release and its .zip asset."""
    tag = f"v{version}"
    if shutil.which("gh") is None:
        print(f"\ngh is not installed: publish by hand as release {tag} at\n"
              f"  https://github.com/claytonkanderson/dungeons-of-warcraft/releases/new\n"
              f"  attaching {zip_path}\n"
              f"(or: winget install GitHub.cli; gh auth login; then rerun with --publish)")
        return
    run(["gh", "release", "create", tag, str(zip_path), "--title",
         f"Dungeons of Warcraft {version}", "--notes",
         f"Build {zip_path.stem}. The game updates itself from this release."])
    print(f"published {tag}")


def copy_docs():
    for src, dst in DOCS:
        shutil.copy(ROOT / src, OUT / dst)
        print(f"  {dst}")


SHIPPED = ["DungeonsOfWarcraft.exe", "setup.exe", "README.txt",
           "LICENSE.txt", "THIRD-PARTY.txt"]


def make_zip():
    """dist/DungeonsOfWarcraft-<version>-<yyyymmdd-hhmm>.zip of the five
    shipped files (never the _build folder a local setup run leaves beside
    them), stamped with the build time so hand-outs tell apart."""
    import zipfile
    from datetime import datetime
    name = OUT.parent / f"DungeonsOfWarcraft-{game_version()}-{datetime.now():%Y%m%d-%H%M}.zip"
    with zipfile.ZipFile(name, "w", zipfile.ZIP_DEFLATED) as z:
        for f in SHIPPED:
            z.write(OUT / f, f"DungeonsOfWarcraft/{f}")
    print(f"\nzip: {name} ({name.stat().st_size / 1e6:.1f} MB)")
    return name


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--only", choices=["exe", "setup", "docs"], default="",
                    help="build just one part (default: everything)")
    ap.add_argument("--no-zip", action="store_true",
                    help="skip the time-stamped zip of the shipped files")
    ap.add_argument("--publish", action="store_true",
                    help="after the zip: create the GitHub release the game updates from")
    args = ap.parse_args()
    version = game_version()
    print(f"version {version}")
    write_asset_versions()
    stamp_export_version(version)
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
    if not args.no_zip:
        z = make_zip()
        if args.publish:
            publish(z, version)


if __name__ == "__main__":
    main()
