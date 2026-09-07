"""Record a survey glide of each named dungeon (--tour) and render it to
video/tours/<dungeon>.mp4, for watching a build for artifacts.

    python tour_videos.py <seconds> <dungeon-id> [<dungeon-id> ...]

Recording runs off-desktop and minimized (only the session log matters);
the render is render_replay.bat. Each dungeon takes about the tour length
to record and one to two times that to render.
"""
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
OVERRIDE = ROOT / "game" / "override.cfg"
OUT = ROOT / "video" / "tours"
OFFDESK = ("[display]\nwindow/size/no_focus=true\n"
           "window/size/initial_position_type=0\n"
           "window/size/initial_position=Vector2i(-32000, -32000)\n")


def tour(did, seconds):
    OVERRIDE.write_text(OFFDESK)
    try:
        run = subprocess.run(
            ["cmd", "/c", str(ROOT / "run_game.bat"), "--", "--fresh",
             f"--dungeon={did}", f"--tour={seconds}", "--offscreen"],
            capture_output=True, text=True, errors="replace", timeout=seconds + 600)
    finally:
        OVERRIDE.unlink(missing_ok=True)
    out = run.stdout + run.stderr
    m = re.search(r"recording session to (.+\.jsonl)", out)
    done = re.search(r"TOUR done: .*", out)
    errors = [l for l in out.splitlines() if "SCRIPT ERROR" in l]
    print(f"  {done.group(0) if done else 'tour did not finish'}"
          + (f"; {len(errors)} script errors" if errors else ""))
    return m.group(1).strip() if m else None


def render(log, mp4):
    run = subprocess.run(["cmd", "/c", str(ROOT / "render_replay.bat"), log, str(mp4)],
                         capture_output=True, text=True, errors="replace", timeout=3600)
    out = run.stdout + run.stderr
    frames = re.search(r"\d+ frames at .*", out)
    print(f"  {frames.group(0) if frames else 'no movie written'}")
    return mp4.exists()


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    seconds = int(sys.argv[1])
    OUT.mkdir(parents=True, exist_ok=True)
    for did in sys.argv[2:]:
        print(f"=== {did}")
        log = tour(did, seconds)
        if not log:
            print("  no session log was written")
            continue
        mp4 = OUT / f"{did}.mp4"
        mp4.unlink(missing_ok=True)
        if render(log, mp4):
            print(f"  wrote {mp4} ({mp4.stat().st_size / 1e6:.1f} MB)")
    print(f"tours in {OUT}")


if __name__ == "__main__":
    main()
