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
        # doors that also swing open on their own: a boss kill, or the cannon
        # event. Every door opens by hand regardless, so this is flavour
        # rather than a gate. The Heavy Doors have no entry because nothing
        # in AzerothCore opens two of them, and the other two are worked by
        # levers that stand on the far side of the door they open.
        doors={"Factory Door": {"boss": "Rhahk'Zor"},
               "Iron Clad Door": {"cannon": "Defias Cannon"}},
        # Footstep surface (see EVENTS in d2/export_sounds.py): the Deadmines
        # is planking and mine timber. Default is "stone".
        footstep="wood",
        # Type-5 GENERIC gameobjects are decoration and are never lootable —
        # except these, which are genuine reward containers modelled as
        # GENERIC. Smite's Chest is the script-spawned drop after Mr. Smite.
        loot_generic=["Smite's Chest"],
    ),
    "ragefire-chasm": dict(
        map_name="orgrimmarinstance", ac_map=389, target_level=18,
        bosses=["Oggleflint", "Taragaman the Hungerer",
                "Jergosh the Invoker", "Bazzalan"],
        final_boss="Taragaman the Hungerer",
        ambience=["ragefirechasm", "ragefire", "orgrimmar"],
        footstep="stone",
    ),
    "wailing-caverns": dict(
        map_name="wailingcaverns", ac_map=43, target_level=22,
        bosses=["Lady Anacondra", "Lord Cobrahn", "Kresh", "Lord Pythas",
                "Skum", "Lord Serpentis", "Verdan the Everliving"],
        # Mutanus is event-summoned (no static spawn); Verdan ends the run
        final_boss="Verdan the Everliving",
        ambience=["wailingcaverns", "wailingcavern", "barrens"],
        footstep="dirt",
    ),
    "shadowfang-keep": dict(
        map_name="shadowfang", ac_map=33, target_level=30,
        bosses=["Rethilgore", "Razorclaw the Butcher", "Baron Silverlaine",
                "Commander Springvale", "Odo the Blindwatcher",
                "Fenrus the Devourer", "Wolf Master Nandos",
                "Archmage Arugal", "Deathsworn Captain"],
        final_boss="Archmage Arugal",
        ambience=["shadowfangkeep", "shadowfang", "silverpine"],
        footstep="stone",
    ),
}
