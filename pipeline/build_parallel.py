"""Build the dungeons several at a time.

Each dungeon's build is independent (everything it writes is under its
own assets/wow/<id> folder) and the CASC reader opens files afresh per
read, so a process pool with one Storage per worker is safe. The longest
dungeons go first, so the last worker is not left alone on Zul'Gurub.
Each worker's output is captured and written by the parent as one block
prefixed with the dungeon's id, so setup.log stays readable.

Ambience is the one thing two dungeons could write at once (two zones
share a loop): the worker writes its .ogg through a temp file and returns
the name; the parent merges the dungeon -> file table into audio.json
after the pool has drained.
"""
import io
import os
import sys
import time
import traceback
from concurrent.futures import ProcessPoolExecutor, as_completed
from pathlib import Path

HERE = Path(__file__).resolve().parent

# seconds a fresh build took per dungeon on one core (a 32-minute run),
# for the order of work and the estimate; the last run's own times, kept
# beside the assets, take precedence
EST_SECONDS = {
    "deadmines": 45, "ragefire-chasm": 9, "wailing-caverns": 46,
    "shadowfang-keep": 81, "blackfathom-deeps": 32, "stockade": 8,
    "gnomeregan": 42, "razorfen-kraul": 55,
    "scarlet-monastery-graveyard": 21, "scarlet-monastery-library": 21,
    "scarlet-monastery-armory": 20, "scarlet-monastery-cathedral": 22,
    "razorfen-downs": 36, "uldaman": 39, "zul-farrak": 90, "maraudon": 68,
    "sunken-temple": 23, "blackrock-depths": 111, "lower-blackrock-spire": 58,
    "dire-maul-east": 74, "dire-maul-west": 79, "dire-maul-north": 71,
    "scholomance": 80, "stratholme": 131, "upper-blackrock-spire": 57,
    "molten-core": 14, "ruins-of-ahnqiraj": 111, "onyxias-lair": 7,
    "temple-of-ahnqiraj": 57, "zul-gurub": 184, "blackwing-lair": 117,
}
DEFAULT_EST = 60

_S = None


def default_jobs():
    return max(1, min((os.cpu_count() or 2) - 1, 6))


def estimates(out_dir):
    """Per-dungeon seconds: the last run's, else the shipped table."""
    est = dict(EST_SECONDS)
    try:
        import json
        saved = json.loads((Path(out_dir) / "build_times.json").read_text())
        for k, v in saved.items():
            est[k] = float(v)
    except Exception:
        pass
    return est


def _init():
    global _S
    sys.path.insert(0, str(HERE))
    sys.modules.pop("config", None)
    from casc import Storage
    _S = Storage()


def _one(did, cfg):
    buf = io.StringIO()
    t0 = time.time()
    ok, amb = False, ""
    old_out, old_err = sys.stdout, sys.stderr
    sys.stdout = sys.stderr = buf
    try:
        import build_dungeon
        ok = bool(build_dungeon.build(_S, did, cfg))
        amb = build_dungeon.LAST_AMBIENCE.get(did, "")
    except SystemExit:
        ok = False
    except Exception:
        traceback.print_exc(file=buf)
        ok = False
    finally:
        sys.stdout, sys.stderr = old_out, old_err
    return did, ok, amb, time.time() - t0, buf.getvalue()


def build_all(dungeons, out_dir, jobs=0, progress=None):
    """dungeons: {id: cfg}. progress(done, total, running_ids, eta_s) after
    each finish. Returns {id: ok}; writes build_times.json and merges the
    ambience table into audio.json."""
    import json
    jobs = jobs or default_jobs()
    est = estimates(out_dir)
    order = sorted(dungeons, key=lambda d: -est.get(d, DEFAULT_EST))
    total_w = sum(est.get(d, DEFAULT_EST) for d in order)
    results, times, ambience = {}, {}, {}
    done_w = 0.0
    t0 = time.time()
    print(f"building {len(order)} dungeons with {jobs} workers "
          f"(about {total_w / jobs / 60:.0f} min on this machine)")
    running = set()
    with ProcessPoolExecutor(max_workers=jobs, initializer=_init) as pool:
        futures = {}
        for did in order:
            futures[pool.submit(_one, did, dungeons[did])] = did
            running.add(did)
        for fut in as_completed(futures):
            did, ok, amb, secs, log = fut.result()
            running.discard(did)
            results[did] = ok
            times[did] = round(secs, 1)
            if amb:
                ambience[did] = amb
            done_w += est.get(did, DEFAULT_EST)
            for line in log.rstrip().splitlines():
                print(f"[{did}] {line}")
            n = len(results)
            elapsed = time.time() - t0
            # the speed so far against the estimate scales what is left,
            # spread over the workers still busy
            speed = elapsed / max(1.0, done_w / jobs)
            left_w = total_w - done_w
            eta = speed * left_w / jobs
            print(f"[{n}/{len(order)}] {did} {'done' if ok else 'FAILED'} in "
                  f"{secs:.0f}s; about {eta / 60:.1f} min left")
            if progress:
                progress(n, len(order), sorted(running), eta)
    try:
        (Path(out_dir) / "build_times.json").write_text(json.dumps(times, indent=1))
    except OSError:
        pass
    audio_json = Path(out_dir) / "wow" / "audio" / "audio.json"
    try:
        man = json.loads(audio_json.read_text()) if audio_json.exists() else {}
        byd = man.get("dungeon_ambience", {})
        byd.update(ambience)
        man["dungeon_ambience"] = byd
        audio_json.parent.mkdir(parents=True, exist_ok=True)
        audio_json.write_text(json.dumps(man, indent=1))
    except (OSError, ValueError) as e:
        print(f"!! could not write the ambience table: {e}")
    failed = [d for d, ok in results.items() if not ok]
    if failed:
        print(f"!! {len(failed)} dungeon(s) failed: {', '.join(failed)}")
    return results
