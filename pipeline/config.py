"""Paths and product selection for the dungeons-of-warcraft pipeline.

WoW-side extraction settings match D:\\tree\\warcraft-art (the repo this
pipeline was forked from); output lands in this repo's assets/wow tree.
"""
import os
from pathlib import Path

WOW_ROOT = Path(os.environ.get("DOW_WOW_ROOT",
                               r"D:\Games\World of Warcraft"))
DATA_DIR = WOW_ROOT / "Data"

# Which TACT product row of .build.info to read. The anniversary
# (2.5.x; built against 2.5.6.69546) and classic_era products share the
# same local archives. The build number is not pinned — Storage reads
# whatever version .build.info reports for this product.
PRODUCT = "wow_anniversary"

REPO = Path(__file__).resolve().parent.parent
ASSETS = Path(os.environ.get("DOW_ASSETS", REPO / "assets"))
RAW = ASSETS / "raw"          # untouched files pulled out of CASC (debug)
OUT = ASSETS / "wow"          # converted: png / gltf ready for the game

# AzerothCore world DB dump: creature spawns, templates, stats.
# The builder downloads the needed files when no local checkout exists.
AC = Path(os.environ.get("DOW_AC_DIR",
                         r"D:\tree\azerothcore-wotlk\data\sql\base\db_world"))
