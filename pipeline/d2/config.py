"""D2 pipeline config, machine-agnostic: the builder points this at the
player's install via environment variables; the dev-machine layout is the
fallback. The MPQ/DCC/DC6/COF decoders live in ./tools (vendored)."""
import os
import sys

D2_DIR = os.environ.get("DOW_D2_DIR", r"E:\D2_Modded")
D2_TOOLS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "tools")
_REPO = os.path.dirname(os.path.dirname(
    os.path.dirname(os.path.abspath(__file__))))
ASSETS = os.environ.get("DOW_ASSETS", os.path.join(_REPO, "assets"))

ARCHIVES = ['patch_d2.mpq', 'd2exp.mpq', 'd2char.mpq', 'd2data.mpq']

sys.path.insert(0, D2_TOOLS)
