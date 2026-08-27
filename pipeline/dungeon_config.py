"""Per-dungeon build configuration: the ~6 lines each dungeon needs.

Bosses are curated by NAME (matched against creature_template at build
time — unmatched names are reported loudly). target_level drives XP
normalization: a full clear is budgeted to carry the character from
roughly target_level-4 to target_level.
"""

DUNGEONS = {
    "deadmines": dict(
        map_name="deadminesinstance", ac_map=36, target_level=26,
        bosses=["Rhahk'Zor", "Sneed's Shredder", "Sneed", "Gilnid",
                "Mr. Smite", "Captain Greenskin", "Cookie",
                "Edwin VanCleef", "Miner Johnson"],
        final_boss="Edwin VanCleef",
        ambience=["deadmines"],
        # VanCleef keeps his hand-tuned cutlasses (attach_id, model, tex)
        hand_tuned={"Edwin VanCleef":
                    [(1, 148115, 148117), (2, 148120, 148124)]},
    ),
    "ragefire-chasm": dict(
        map_name="orgrimmarinstance", ac_map=389, target_level=18,
        bosses=["Oggleflint", "Taragaman the Hungerer",
                "Jergosh the Invoker", "Bazzalan"],
        final_boss="Taragaman the Hungerer",
        ambience=["ragefirechasm", "ragefire", "orgrimmar"],
    ),
    "wailing-caverns": dict(
        map_name="wailingcaverns", ac_map=43, target_level=22,
        bosses=["Lady Anacondra", "Lord Cobrahn", "Kresh", "Lord Pythas",
                "Skum", "Lord Serpentis", "Verdan the Everliving"],
        # Mutanus is event-summoned (no static spawn); Verdan ends the run
        final_boss="Verdan the Everliving",
        ambience=["wailingcaverns", "wailingcavern", "barrens"],
    ),
    "shadowfang-keep": dict(
        map_name="shadowfang", ac_map=33, target_level=30,
        bosses=["Rethilgore", "Razorclaw the Butcher", "Baron Silverlaine",
                "Commander Springvale", "Odo the Blindwatcher",
                "Fenrus the Devourer", "Wolf Master Nandos",
                "Archmage Arugal", "Deathsworn Captain"],
        final_boss="Archmage Arugal",
        ambience=["shadowfangkeep", "shadowfang", "silverpine"],
    ),
}
