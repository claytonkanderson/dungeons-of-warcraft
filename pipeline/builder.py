"""Dungeons of Warcraft asset builder.

Generates every game asset from the player's OWN installs — nothing from
Blizzard ships with the game. Requires:

  - Diablo II (1.14 or an install with the classic MPQs in its folder)
  - World of Warcraft Classic Anniversary (the local game data)

Two ways to run. Launched with no arguments (a double-click on setup.exe)
it opens a small window to pick the two install folders and watch the
build. Given paths, it builds headlessly from the command line:

  python builder.py --d2 "C:\\Program Files (x86)\\Diablo II" ^
                    --wow "C:\\Program Files (x86)\\World of Warcraft" ^
                    [--out <assets dir>] [--ac <azerothcore db_world dir>]

Spawn/stat data comes from the open-source AzerothCore project (AGPL). The
rows the configured dungeons need ship inside setup (pipeline/ac_data,
made by trim_ac.py), so a build needs no internet and always reads a
schema the loaders were checked against. --refresh-ac (developers only)
downloads the full current dumps instead — an upstream schema change can
then break the column lookups, so re-trim with trim_ac.py and rebuild
before shipping; --ac points at a local checkout.

Both install paths are found automatically where possible (the Battle.net
product database, the registry, the usual folders); the window pre-fills
them and the command line uses them when --d2/--wow are omitted.
"""
import argparse
import json
import os
import re
import sys
import time
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent

# Frozen by PyInstaller in onefile mode, __file__ lives in the temporary
# extraction directory, so anything derived from it lands in %TEMP%. Assets
# have to sit beside the executable, which is where paths.gd looks for them.
BESIDE_EXE = (Path(sys.executable).resolve().parent if getattr(sys, "frozen", False)
              else HERE.parent)

# Everything setup generates — assets, setup.log, the remembered paths — lives
# in one _build folder beside the executables, so the portable install is the
# two exes, the docs, and _build. paths.gd looks for assets there in an
# exported game. From a source checkout the repo root is the build root
# instead (repo/assets, which the editor reads as ../assets), so developer
# layout is unchanged. Created on demand; nothing assumes it exists.
BUILD_DIR = (BESIDE_EXE / "_build" if getattr(sys, "frozen", False)
             else BESIDE_EXE)

# Every AzerothCore table the build reads. The trimmed copies in
# pipeline/ac_data (vendored, bundled into setup.exe) are what a build
# normally reads; keep this list in step with the `AC / "<name>.sql"` reads
# in build_dungeon.py, build_creatures.py and dungeon_common.py, and with
# trim_ac.py, which produces those copies — a table missing from either
# only shows up as a failed build on a player's machine.
AC_FILES = [
    "creature.sql", "creature_template.sql", "creature_template_model.sql",
    "creature_equip_template.sql", "item_template.sql",
    "creature_classlevelstats.sql", "areatrigger_teleport.sql",
    "gameobject.sql", "gameobject_template.sql",
]
AC_URL = ("https://raw.githubusercontent.com/azerothcore/azerothcore-wotlk/"
          "master/data/sql/base/db_world/")


# Build progress: every stage announces itself here, so the setup window
# can show a bar instead of the stream of detail (which still goes to the
# log). `total` is set by run_build from the stages it is about to run.
_progress = {"done": 0, "total": 0, "cb": None}


def stage(label):
    _progress["done"] += 1
    done, total = _progress["done"], max(_progress["total"], _progress["done"])
    print(f"\n--- [{done}/{total}] {label} ---")
    if _progress["cb"]:
        try:
            _progress["cb"](label, done, total)
        except Exception:
            pass


def fail(msg):
    print(f"\nERROR: {msg}")
    sys.exit(1)


def game_root(path):
    """The install folder for what the picker holds. The setup window shows
    the game's .exe (what a player recognises); the build wants the folder
    it sits in. A folder pasted straight into the field passes through."""
    path = (path or "").strip()
    return os.path.dirname(path) if os.path.isfile(path) else path


def validate_d2(d2):
    """'' if the folder looks like a Diablo II install, else why not.
    Shared by the CLI check and the picker so both judge a folder alike."""
    if not d2:
        return "no folder chosen"
    for probe in ("patch_d2.mpq", "d2data.mpq"):
        if not (Path(d2) / probe).exists():
            return f"{probe} not found here"
    return ""


def validate_wow(wow):
    """'' if the folder looks like a WoW Anniversary install, else why not."""
    if not wow:
        return "no folder chosen"
    if not (Path(wow) / "Data").is_dir():
        return "no Data folder here"
    if not (Path(wow) / ".build.info").exists():
        return "no .build.info here"
    return ""


# ---------------------------------------------------------------------------
# Finding the installs without asking. Diablo II leaves its folder in the
# registry; Battle.net records every product's install folder in its
# product database and the uninstall entries; both games have habitual
# folders. Every candidate is checked with the same validators the picker
# uses, so a stale registry key cannot pass.
# ---------------------------------------------------------------------------
WOW_PRODUCT_DIRS = ["_anniversary_", "_classic_era_", "_classic_", "_retail_", ""]


def _reg_values(subkeys, names):
    """Every string value found under the given registry subkeys, in HKCU
    and HKLM, both the 64-bit and the WOW6432Node views."""
    out = []
    try:
        import winreg
    except ImportError:
        return out
    for root in (winreg.HKEY_CURRENT_USER, winreg.HKEY_LOCAL_MACHINE):
        for sub in subkeys:
            for view in (0, getattr(winreg, "KEY_WOW64_32KEY", 0),
                         getattr(winreg, "KEY_WOW64_64KEY", 0)):
                try:
                    k = winreg.OpenKey(root, sub, 0, winreg.KEY_READ | view)
                except OSError:
                    continue
                for n in names:
                    try:
                        v, _ = winreg.QueryValueEx(k, n)
                        if isinstance(v, str) and v.strip():
                            out.append(v.strip().strip('"'))
                    except OSError:
                        pass
                winreg.CloseKey(k)
    return out


def _uninstall_locations(match):
    """InstallLocation of every uninstall entry whose display name contains
    match (case-insensitive)."""
    out = []
    try:
        import winreg
    except ImportError:
        return out
    subs = [r"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
            r"SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"]
    for root in (winreg.HKEY_LOCAL_MACHINE, winreg.HKEY_CURRENT_USER):
        for sub in subs:
            try:
                k = winreg.OpenKey(root, sub)
            except OSError:
                continue
            i = 0
            while True:
                try:
                    name = winreg.EnumKey(k, i)
                except OSError:
                    break
                i += 1
                try:
                    e = winreg.OpenKey(k, name)
                    disp, _ = winreg.QueryValueEx(e, "DisplayName")
                    if match.lower() in str(disp).lower():
                        loc, _ = winreg.QueryValueEx(e, "InstallLocation")
                        if str(loc).strip():
                            out.append(str(loc).strip().strip('"'))
                except OSError:
                    pass
    return out


def _battlenet_paths():
    """Install folders recorded in Battle.net's product database. The file is
    a protobuf; the paths inside are plain text, so they are scanned for."""
    out = []
    pd = os.environ.get("PROGRAMDATA", r"C:\ProgramData")
    db = Path(pd) / "Battle.net" / "Agent" / "product.db"
    try:
        data = db.read_bytes()
    except OSError:
        return out
    for m in re.finditer(rb"[A-Za-z]:[\\/][^\x00-\x1f\"<>|?*]{2,240}", data):
        try:
            out.append(m.group(0).decode("utf-8"))
        except UnicodeDecodeError:
            pass
    return out


def _fixed_drives():
    drives = []
    for letter in "CDEFGHIJKLMNOPQRSTUVWXYZ":
        if os.path.isdir(f"{letter}:\\"):
            drives.append(f"{letter}:\\")
    return drives


def _program_files():
    out = []
    for var in ("ProgramFiles(x86)", "ProgramFiles", "ProgramW6432"):
        v = os.environ.get(var)
        if v:
            out.append(v)
    return out


def detect_d2():
    """The Diablo II install folder, or '' when nothing validates."""
    cands = _reg_values([r"Software\Blizzard Entertainment\Diablo II",
                         r"SOFTWARE\Blizzard Entertainment\Diablo II"],
                        ["InstallPath", "Save Path"])
    cands += _uninstall_locations("Diablo II")
    for base in _program_files() + _fixed_drives():
        for sub in ("Diablo II", r"Games\Diablo II", r"Blizzard\Diablo II",
                    r"Program Files (x86)\Diablo II"):
            cands.append(os.path.join(base, sub))
    seen = set()
    for c in cands:
        c = os.path.normpath(c)
        if c in seen:
            continue
        seen.add(c)
        if os.path.isdir(c) and not validate_d2(c):
            return c
    return ""


def detect_wow():
    """The WoW product folder (the one holding Data and .build.info), or ''."""
    roots = _reg_values([r"SOFTWARE\Blizzard Entertainment\World of Warcraft",
                         r"Software\Blizzard Entertainment\World of Warcraft"],
                        ["InstallPath", "GamePath"])
    roots += _uninstall_locations("World of Warcraft")
    roots += _battlenet_paths()
    for base in _program_files() + _fixed_drives():
        for sub in ("World of Warcraft", r"Games\World of Warcraft",
                    r"Blizzard\World of Warcraft",
                    r"Program Files (x86)\World of Warcraft"):
            roots.append(os.path.join(base, sub))
    seen = set()
    for r in roots:
        r = os.path.normpath(r)
        # a recorded path may already be the product folder, or its parent,
        # or a file inside it
        bases = [r, os.path.dirname(r), os.path.dirname(os.path.dirname(r))]
        for b in bases:
            for sub in WOW_PRODUCT_DIRS:
                c = os.path.normpath(os.path.join(b, sub)) if sub else b
                if c in seen:
                    continue
                seen.add(c)
                if os.path.isdir(c) and not validate_wow(c):
                    return c
    return ""


def display_path(folder, exe_names):
    """What the picker shows for a detected folder: the game's own exe when
    it is there (what a player recognises), else the folder."""
    for n in exe_names:
        f = os.path.join(folder, n)
        if os.path.isfile(f):
            return f
    return folder


D2_EXES = ["Diablo II.exe", "Game.exe"]
WOW_EXES = ["World of Warcraft Launcher.exe", "WowClassic.exe", "Wow.exe"]


def check_d2(d2):
    msg = validate_d2(d2)
    if msg:
        fail(f"{msg} ({d2}) — point --d2 at the Diablo II install folder that "
             "contains the .mpq files")


def check_wow(wow):
    msg = validate_wow(wow)
    if msg:
        fail(f"{msg} ({wow}) — point --wow at the WoW Classic Anniversary "
             "install (the folder containing Data and .build.info)")


# The trimmed AzerothCore rows for the configured dungeons. Under PyInstaller
# HERE is the extraction dir and build_dist.py adds ac_data beside d2/.
AC_BUNDLED = HERE / "ac_data"


def ensure_ac(ac_dir, cache, refresh=False):
    if not ac_dir and not refresh:
        missing = [f for f in AC_FILES if not (AC_BUNDLED / f).exists()]
        if not missing:
            return AC_BUNDLED
        print(f"bundled AzerothCore data incomplete ({', '.join(missing[:3])}"
              f"{', ...' if len(missing) > 3 else ''}); downloading instead")
    if ac_dir:
        missing = [f for f in AC_FILES if not Path(ac_dir, f).exists()]
        if not missing:
            return Path(ac_dir)
        # say so rather than silently downloading instead: a half-applied
        # flag is worse than a rejected one
        fail(f"--ac {ac_dir} is missing {len(missing)} of the {len(AC_FILES)} "
             f"files this build needs ({', '.join(missing[:3])}"
             f"{', ...' if len(missing) > 3 else ''}). Point it at an "
             "AzerothCore data/sql/base/db_world directory, or drop the flag "
             "to download them.")
    cache.mkdir(parents=True, exist_ok=True)
    for f in AC_FILES:
        dest = cache / f
        if dest.exists() and dest.stat().st_size > 0 and not refresh:
            continue
        print(f"downloading AzerothCore data: {f} ...")
        # download to a temp name and rename, so an interrupted transfer
        # cannot leave a truncated file that later runs treat as complete
        part = dest.with_suffix(dest.suffix + ".part")
        try:
            urllib.request.urlretrieve(AC_URL + f, part)
            part.replace(dest)
        except OSError as e:
            part.unlink(missing_ok=True)
            fail(f"could not download {f} from AzerothCore ({e}). Check your "
                 "internet connection, or pass --ac pointing at a local "
                 "AzerothCore data/sql/base/db_world directory.")
    return cache


def run_d2_stages():
    sys.path.insert(0, str(HERE / "d2"))
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
    stages = [
        ("game tables", export_tables.build),
        ("D2 interface art", export_ui.build),
        ("missile sprites", export_missiles.build),
        ("Amazon animation sheets", export_amazon.build),
        ("menu paperdoll layers", export_paperdoll.build),
        ("summon sprites", lambda: (
            setattr(export_monsters, "ROSTER", {"VK": "valkyrie"}),
            export_monsters.build())),
        ("item catalog + art", export_items.build),
        ("uniques / sets / affixes", export_affixes.build),
        ("item stat text + fonts", lambda: (
            export_statdisplay.export_fonts(),
            export_statdisplay.export_statdisplay())),
        ("D2 sound effects", export_sounds.build),
    ]
    for label, fn in stages:
        t0 = time.time()
        stage(f"Diablo II: {label}")
        fn()
        print(f"    ({time.time() - t0:.0f}s)")
    import export_setbonus
    stage("Diablo II: set bonuses")
    export_setbonus.main()


D2_STAGE_COUNT = 11      # the stages above plus set bonuses


def run_wow_stages(only=""):
    sys.path.insert(0, str(HERE))
    # the D2 stages import their own module also named "config"; make sure
    # the WoW stages resolve pipeline/config.py fresh
    sys.modules.pop("config", None)
    import build_dungeon
    import build_audio
    import build_backdrops
    from casc import Storage
    from dungeon_config import DUNGEONS
    stage("World of Warcraft: opening the local game storage")
    s = Storage()
    for did, cfg in DUNGEONS.items():
        if only and did != only:
            continue
        t0 = time.time()
        stage("World of Warcraft: " + did.replace("-", " ").title())
        build_dungeon.build(s, did, cfg)
        print(f"    ({time.time() - t0:.0f}s)")
    stage("World of Warcraft: menu backdrops")
    build_backdrops.build(s)
    stage("World of Warcraft: soundscape")
    build_audio.main()


def wow_stage_count(only=""):
    sys.path.insert(0, str(HERE))
    from dungeon_config import DUNGEONS
    return 1 + (1 if only else len(DUNGEONS)) + 2


def run_build(d2, wow, out="", ac="", skip_d2=False, skip_wow=False,
              only_dungeon="", refresh_ac=False):
    """Run the asset build. Both the CLI and the picker call this; it assumes
    d2/wow already passed check_d2/check_wow (the picker validates first, the
    CLI calls the checks below). Progress goes to stdout, which the picker
    mirrors into its log pane."""
    if skip_d2 and skip_wow:
        fail("--skip-d2 and --skip-wow together leave nothing to build.")
    if only_dungeon:
        # dungeon_config imports nothing, so loading it here cannot poison the
        # `config` module name the D2 and WoW halves each resolve differently
        sys.path.insert(0, str(HERE))
        from dungeon_config import DUNGEONS as _D
        if only_dungeon not in _D:
            fail(f"unknown dungeon '{only_dungeon}'. Configured: "
                 f"{', '.join(sorted(_D))}")

    check_d2(d2)
    check_wow(wow)
    out_dir = Path(out) if out else BUILD_DIR / "assets"
    out_dir.mkdir(parents=True, exist_ok=True)
    if skip_d2 and not (out_dir / "gamedata.json").exists():
        fail(f"--skip-d2 expects the Diablo II assets to be in {out_dir} "
             "already, but gamedata.json is not there. Run once without it.")
    ac_dir = ensure_ac(ac, out_dir / "_accache", refresh_ac)

    os.environ["DOW_D2_DIR"] = str(Path(d2))
    os.environ["DOW_WOW_ROOT"] = str(Path(wow))
    os.environ["DOW_ASSETS"] = str(out_dir)
    os.environ["DOW_AC_DIR"] = str(ac_dir)

    _progress["done"] = 0
    _progress["total"] = (0 if skip_d2 else D2_STAGE_COUNT) \
        + (0 if skip_wow else wow_stage_count(only_dungeon))
    t0 = time.time()
    if not skip_d2:
        run_d2_stages()
    if not skip_wow:
        run_wow_stages(only_dungeon)
    print(f"\nALL DONE in {(time.time() - t0) / 60:.1f} min -> {out_dir}")
    print("Launch the game — the dungeon ladder is waiting.")


def run_gui():
    """The setup window: pick the two install folders, watch the build run.
    Shown when the executable is launched with no arguments (a double-click).
    Returns False if a desktop/Tk is unavailable, so the caller can fall back
    to printing CLI usage. Everything here is stdlib (tkinter) so it survives
    the onefile freeze without extra dependencies."""
    try:
        import queue
        import threading
        import tkinter as tk
        from tkinter import filedialog, ttk
    except Exception:
        return False

    prefs_file = BUILD_DIR / "setup_paths.json"
    prefs = {}
    try:
        prefs = json.loads(prefs_file.read_text())
    except Exception:
        prefs = {}

    try:
        root = tk.Tk()
    except Exception:
        return False       # no display (headless) — fall back to CLI usage
    root.title("Dungeons of Warcraft — Setup")
    root.minsize(700, 360)

    state = {"d2": prefs.get("d2", ""), "wow": prefs.get("wow", ""),
             "running": False}
    # remembered paths that still validate win; otherwise look for the games
    if validate_d2(game_root(state["d2"])):
        found = detect_d2()
        if found:
            state["d2"] = display_path(found, D2_EXES)
    if validate_wow(game_root(state["wow"])):
        found = detect_wow()
        if found:
            state["wow"] = display_path(found, WOW_EXES)

    header = tk.Label(root, justify="left", anchor="w", padx=12, pady=8,
                      text="Point Setup at your own Diablo II and World of "
                           "Warcraft installs.\nNothing from either game is "
                           "included — the assets are built here on your PC.")
    header.pack(fill="x")

    rows = tk.Frame(root, padx=12)
    rows.pack(fill="x")
    rows.columnconfigure(1, weight=1)

    d2_var = tk.StringVar(value=state["d2"])
    wow_var = tk.StringVar(value=state["wow"])
    d2_status = tk.Label(rows, anchor="w", width=34)
    wow_status = tk.Label(rows, anchor="w", width=34)

    def refresh():
        msg = validate_d2(game_root(d2_var.get()))
        d2_status.config(text=("OK — Diablo II found" if not msg else msg),
                         fg=("#177245" if not msg else "#a11"))
        msg2 = validate_wow(game_root(wow_var.get()))
        wow_status.config(text=("OK — WoW Anniversary found" if not msg2
                                else msg2),
                          fg=("#177245" if not msg2 else "#a11"))
        can = not msg and not msg2 and not state["running"]
        build_btn.config(state=("normal" if can else "disabled"))

    def browse(var, exe_name):
        # The field shows the game's .exe; game_root() turns it into the
        # install folder wherever the folder is actually needed.
        start = game_root(var.get()) or os.path.expanduser("~")
        picked = filedialog.askopenfilename(
            title=f"Select {exe_name}",
            initialdir=start if os.path.isdir(start) else os.path.expanduser("~"),
            filetypes=[("Program", "*.exe"), ("All files", "*.*")])
        if picked:
            var.set(os.path.normpath(picked))
            refresh()

    def detect_both():
        d2 = detect_d2()
        wow = detect_wow()
        if d2:
            d2_var.set(display_path(d2, D2_EXES))
        if wow:
            wow_var.set(display_path(wow, WOW_EXES))
        status_lbl.config(fg="#333", text=(
            "Found both installs." if d2 and wow else
            "Found Diablo II only — browse to WoW." if d2 else
            "Found WoW only — browse to Diablo II." if wow else
            "Neither install found — use Browse."))
        refresh()

    hint = dict(fg="#666", anchor="w", justify="left")
    tk.Label(rows, text="Diablo II", anchor="w").grid(
        row=0, column=0, sticky="w", pady=(8, 0))
    tk.Entry(rows, textvariable=d2_var).grid(
        row=0, column=1, sticky="ew", padx=6, pady=(8, 0))
    tk.Button(rows, text="Browse…",
              command=lambda: browse(d2_var, "Diablo II.exe")
              ).grid(row=0, column=2, pady=(8, 0))
    tk.Label(rows, text="Browse to Diablo II.exe - the same folder should "
             "contain d2data.mpq", **hint).grid(
        row=1, column=1, columnspan=2, sticky="w", padx=6)
    d2_status.grid(row=2, column=1, sticky="w", padx=6)

    tk.Label(rows, text="World of Warcraft", anchor="w").grid(
        row=3, column=0, sticky="w", pady=(10, 0))
    tk.Entry(rows, textvariable=wow_var).grid(
        row=3, column=1, sticky="ew", padx=6, pady=(10, 0))
    tk.Button(rows, text="Browse…",
              command=lambda: browse(wow_var, "World of Warcraft Launcher.exe")
              ).grid(row=3, column=2, pady=(10, 0))
    tk.Label(rows, text="Browse to World of Warcraft Launcher.exe - same folder "
             "should contain Data and .build.info", **hint).grid(
        row=4, column=1, columnspan=2, sticky="w", padx=6)
    wow_status.grid(row=5, column=1, sticky="w", padx=6)

    d2_var.trace_add("write", lambda *_: refresh())
    wow_var.trace_add("write", lambda *_: refresh())

    tk.Label(root, anchor="w", padx=12, fg="#444", pady=(6),
             text="Assets will be built in:  %s" % (BUILD_DIR / "assets")).pack(
        fill="x", pady=(8, 0))

    # the build shows as one bar and one line — the stream of detail goes
    # to setup.log, which is what to send if something goes wrong
    prog = tk.Frame(root, padx=12)
    prog.pack(fill="x", pady=(6, 0))
    build_lbl = tk.Label(prog, anchor="w", justify="left", fg="#333",
                         wraplength=660)
    build_lbl.pack(fill="x")
    pbar = ttk.Progressbar(prog, orient="horizontal", mode="determinate",
                           maximum=1, value=0)
    pbar.pack(fill="x", pady=(4, 2))
    stage_lbl = tk.Label(prog, anchor="w", fg="#666")
    stage_lbl.pack(fill="x")
    log_path = BUILD_DIR / "setup.log"

    bar = tk.Frame(root, padx=12, pady=8)
    bar.pack(fill="x")
    status_lbl = tk.Label(bar, text="", anchor="w", wraplength=440,
                          justify="left")
    status_lbl.pack(side="left")
    build_btn = tk.Button(bar, text="Build assets")
    build_btn.pack(side="right")
    tk.Button(bar, text="Detect installs", command=detect_both).pack(
        side="right", padx=(0, 8))

    def open_log():
        try:
            os.startfile(log_path)
        except Exception:
            status_lbl.config(text=f"Log: {log_path}", fg="#333")

    tk.Button(bar, text="Open log", command=open_log).pack(
        side="right", padx=(0, 8))

    q = queue.Queue()

    class _Tee:
        """Fan the build's stdout to the real console and the log pane."""
        def __init__(self, orig):
            self.orig = orig

        def write(self, s):
            if self.orig:
                try:
                    self.orig.write(s)
                except Exception:
                    pass
            q.put(s)

        def flush(self):
            if self.orig:
                try:
                    self.orig.flush()
                except Exception:
                    pass

    def worker(d2, wow):
        old_out, old_err = sys.stdout, sys.stderr
        sys.stdout = sys.stderr = _Tee(old_out)
        _progress["cb"] = lambda label, done, total: q.put(
            ("__stage__", label, done, total))
        ok = True
        try:
            run_build(d2, wow)
        except SystemExit:          # fail() inside the build; message already logged
            ok = False
        except Exception as e:
            print(f"\nERROR: {e}")
            ok = False
        finally:
            _progress["cb"] = None
            sys.stdout, sys.stderr = old_out, old_err
            q.put(("__done__", ok))

    def start_build():
        # remember what the player typed/picked (the .exe) so it displays the
        # same way next time; hand the build the folders it actually needs
        prefs_file.write_text(json.dumps({"d2": d2_var.get(),
                                          "wow": wow_var.get()}))
        d2, wow = game_root(d2_var.get()), game_root(wow_var.get())
        state["running"] = True
        build_btn.config(state="disabled")
        build_lbl.config(text="Building game at %s\nfrom %s\nand %s"
                         % (BUILD_DIR / "assets", d2, wow))
        stage_lbl.config(text="Starting…")
        pbar.config(value=0, maximum=1)
        status_lbl.config(text="This takes 5–10 minutes.", fg="#333")
        threading.Thread(target=worker, args=(d2, wow), daemon=True).start()

    build_btn.config(command=start_build)

    def drain():
        try:
            while True:
                item = q.get_nowait()
                if isinstance(item, tuple) and item and item[0] == "__stage__":
                    _, label, done, total = item
                    pbar.config(maximum=total, value=done - 1)
                    stage_lbl.config(text=f"{done} of {total}: {label}")
                    continue
                if isinstance(item, tuple) and item and item[0] == "__done__":
                    state["running"] = False
                    ok = item[1]
                    if ok:
                        pbar.config(value=pbar["maximum"])
                        stage_lbl.config(text="Finished.")
                    status_lbl.config(
                        text=("Done — close this and run DungeonsOfWarcraft.exe"
                              if ok else "Build failed — see setup.log "
                              "(the Open log button)."),
                        fg=("#177245" if ok else "#a11"))
                    refresh()
                    continue
                # the detail goes to the log; only an error is shown here
                text = str(item)
                if "ERROR:" in text:
                    stage_lbl.config(text=text.strip()[:200], fg="#a11")
        except queue.Empty:
            pass
        root.after(80, drain)

    refresh()
    root.after(80, drain)
    root.mainloop()
    return True


def attach_console():
    """The frozen setup.exe is a windowed build (no console of its own), so a
    double-click shows only the window. Run from a terminal with arguments,
    it attaches to that terminal so its output goes where the user is
    looking. Without one (or on a non-Windows host) stdout stays whatever
    it is; the log file receives everything either way."""
    if os.name != "nt" or not getattr(sys, "frozen", False):
        return
    if sys.stdout is not None and sys.stderr is not None:
        return
    try:
        import ctypes
        if ctypes.windll.kernel32.AttachConsole(-1):
            sys.stdout = open("CONOUT$", "w", encoding="utf-8", buffering=1)
            sys.stderr = sys.stdout
            print()     # step past the shell prompt already on that line
    except Exception:
        pass


def main():
    if len(sys.argv) > 1:
        attach_console()
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--d2", default="",
                    help="Diablo II install folder (default: auto-detected)")
    ap.add_argument("--wow", default="",
                    help="WoW Classic Anniversary install folder (default: "
                         "auto-detected)")
    ap.add_argument("--out", default="",
                    help="assets output dir (default: ./assets beside the game)")
    ap.add_argument("--ac", default="",
                    help="local AzerothCore db_world dir (default: the trimmed "
                         "data bundled with setup)")
    ap.add_argument("--refresh-ac", action="store_true",
                    help="developer: download the current AzerothCore dumps "
                         "instead of the bundled rows (a schema change "
                         "upstream can break the build; re-trim with "
                         "trim_ac.py and rebuild before shipping)")
    ap.add_argument("--detect", action="store_true",
                    help="print the installs found automatically, then exit")
    ap.add_argument("--skip-d2", action="store_true",
                    help="skip the Diablo II stages (art, items, sounds)")
    ap.add_argument("--skip-wow", action="store_true",
                    help="skip the WoW stages (dungeons, backdrops, audio)")
    ap.add_argument("--only-dungeon", default="", help=argparse.SUPPRESS)
    args = ap.parse_args()

    # Everything printed from here on is also written to setup.log beside the
    # executable, so a player can send the log of a failed build without
    # having to capture a console window. Both the window and the CLI route
    # their output through sys.stdout, so one tee covers both.
    log_path = BUILD_DIR / "setup.log"
    try:
        BUILD_DIR.mkdir(parents=True, exist_ok=True)
        log_f = open(log_path, "w", encoding="utf-8")
    except OSError:
        log_f = None

    class _LogTee:
        def __init__(self, orig):
            self.orig = orig

        def write(self, s):
            if self.orig:
                try:
                    self.orig.write(s)
                except Exception:
                    pass
            if log_f:
                try:
                    log_f.write(s)
                    log_f.flush()
                except Exception:
                    pass

        def flush(self):
            if self.orig:
                try:
                    self.orig.flush()
                except Exception:
                    pass

    if log_f:
        sys.stdout = _LogTee(sys.stdout)
        sys.stderr = _LogTee(sys.stderr)
        print(f"log: {log_path}")

    # No install paths given (a double-click) — open the picker. If there is no
    # desktop to draw it on, fall through to the usual CLI error.
    if args.detect:
        d2 = detect_d2()
        wow = detect_wow()
        print(f"Diablo II:         {d2 or 'not found'}")
        print(f"World of Warcraft: {wow or 'not found'}")
        return
    # the window only for a bare double-click; any flag at all (a dungeon
    # to rebuild, --skip-d2 ...) means a scripted run, which must never
    # block on a window
    if len(sys.argv) == 1:
        if run_gui():
            return
    # command line: whatever was not given is looked for
    if not args.d2:
        args.d2 = detect_d2()
        print(f"Diablo II: {args.d2 or 'not found'} (auto-detected)")
    if not args.wow:
        args.wow = detect_wow()
        print(f"World of Warcraft: {args.wow or 'not found'} (auto-detected)")
    if not args.d2 or not args.wow:
        fail("could not find both installs. Run with no arguments for the setup "
             'window, or pass --d2 "…" --wow "…" to build from the command line.')

    run_build(args.d2, args.wow, args.out, args.ac,
              args.skip_d2, args.skip_wow, args.only_dungeon, args.refresh_ac)


if __name__ == "__main__":
    main()
