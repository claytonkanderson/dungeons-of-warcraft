"""Prove the self-update, against the published release or locally.

  python pipeline/test_update.py --local     # against this checkout's own build
  python pipeline/test_update.py             # against the release on GitHub
  python pipeline/test_update.py --no-launch # stage only

--local needs nothing published: the checkout's current version is
exported and zipped, a small web server on 127.0.0.1 serves it with a
release listing shaped like GitHub's, and the throwaway is started with
--update-url= pointing there. The game restarts without that flag, so
after the swap it asks GitHub as usual (and finds nothing newer).

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
import http.server
import json
import re
import shutil
import subprocess
import sys
import threading
import time
from functools import partial
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
DIST = ROOT / "dist" / "DungeonsOfWarcraft"
TEST = ROOT / "dist" / "updtest"
VERSION_GD = ROOT / "game" / "scripts" / "version.gd"
LOCAL_PORT = 8765


class _Quiet(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *args):
        pass


def serve_local(zip_path, version):
    """dist/ over http on 127.0.0.1, with latest.json shaped like GitHub's
    releases/latest so the updater reads it unchanged. Returns the server
    (shut it down when done) and the listing's URL."""
    listing = DIST.parent / "latest.json"
    listing.write_text(json.dumps({
        "tag_name": "v" + version,
        "assets": [{"name": zip_path.name,
                    "browser_download_url": f"http://127.0.0.1:{LOCAL_PORT}/{zip_path.name}"}],
    }))
    handler = partial(_Quiet, directory=str(DIST.parent))
    srv = http.server.ThreadingHTTPServer(("127.0.0.1", LOCAL_PORT), handler)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    return srv, f"http://127.0.0.1:{LOCAL_PORT}/latest.json"


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
    ap.add_argument("--local", action="store_true",
                    help="serve this checkout's build from 127.0.0.1 as the latest release")
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
    if not (DIST / "setup.exe").exists():
        sys.exit(f"build the release first: {DIST} is missing setup.exe "
                 "(python pipeline/build_dist.py --only setup --no-zip)")
    srv, update_url = None, ""
    if args.local:
        # the checkout's current version, zipped as build_dist.py ships it
        sys.path.insert(0, str(HERE))
        import build_dist
        print(f"exporting the checkout at {cur} as the release to serve")
        export()
        zip_path = build_dist.make_zip()
        srv, update_url = serve_local(zip_path, cur)
        print(f"serving {zip_path.name} at {update_url}")
    if not (DIST / "DungeonsOfWarcraft.exe").exists():
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
    stamp = (TEST / "DungeonsOfWarcraft.exe").stat().st_mtime
    print(f"staged {TEST}: executable {old} ({lower}); the release build is {released} ({cur})")
    if args.no_launch:
        print("launch dist/updtest/DungeonsOfWarcraft.exe and watch the menu's bottom line")
        return

    print("launching; the menu should say 'Updating to %s: downloading', then restart" % cur)
    # detached, as a double-click would start it: the game's own updater
    # script then owns the restart
    cmd = [str(TEST / "DungeonsOfWarcraft.exe")]
    if update_url:
        cmd += ["--", "--update-url=" + update_url]
    subprocess.Popen(cmd, cwd=str(TEST),
                     creationflags=subprocess.DETACHED_PROCESS | subprocess.CREATE_NEW_PROCESS_GROUP,
                     close_fds=True)
    for i in range(24):
        time.sleep(5)
        # watched by time stamp: reading the file would hold it open, and
        # a file held open cannot be moved over on Windows
        try:
            if (TEST / "DungeonsOfWarcraft.exe").stat().st_mtime == stamp:
                continue
        except OSError:
            continue
        time.sleep(3)
        now = md5(TEST / "DungeonsOfWarcraft.exe")
        if now == released:
            print(f"after {5 * (i + 1)} s the folder's executable is the release build: "
                  f"the update applied and the game restarted itself")
            print("close that game window when you are done; dist/updtest can be deleted")
            _stop(srv)
            return
    print("the executable did not change in two minutes: check the menu's bottom line "
          "and %APPDATA%\\Godot\\app_userdata\\Dungeons of Warcraft\\logs\\godot.log")
    _stop(srv)


def _stop(srv):
    if srv is not None:
        srv.shutdown()
        try:
            (DIST.parent / "latest.json").unlink()
        except OSError:
            pass


if __name__ == "__main__":
    main()
