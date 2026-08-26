"""Paths and product selection for the amazon-deadmines pipeline.

WoW-side extraction settings match D:\\tree\\warcraft-art (the repo this
pipeline was forked from); output lands in this repo's assets/wow tree.
"""
from pathlib import Path

WOW_ROOT = Path(r"D:\Games\World of Warcraft")
DATA_DIR = WOW_ROOT / "Data"

# Which TACT product row of .build.info to read. The anniversary (2.5.5)
# and classic_era products share the same local archives.
PRODUCT = "wow_anniversary"

REPO = Path(__file__).resolve().parent.parent
ASSETS = REPO / "assets"
RAW = ASSETS / "raw"          # untouched files pulled out of CASC (debug)
OUT = ASSETS / "wow"          # converted: png / gltf ready for the game

# AzerothCore world DB dump: creature spawns, templates, stats
AC = Path(r"D:\tree\azerothcore-wotlk\data\sql\base\db_world")
