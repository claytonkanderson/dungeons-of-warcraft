"""Per-dungeon build configuration: the ~6 lines each dungeon needs.

Bosses are curated by NAME (matched against creature_template at build
time — unmatched names are reported loudly). target_level drives XP
normalization: a full clear is budgeted to carry the character from
roughly target_level-4 to target_level.
"""

DUNGEONS = {
    "deadmines": dict(
        map_name="deadminesinstance", ac_map=36, target_level=15,
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
        map_name="orgrimmarinstance", ac_map=389, target_level=5,
        bosses=["Oggleflint", "Taragaman the Hungerer",
                "Jergosh the Invoker", "Bazzalan"],
        final_boss="Taragaman the Hungerer",
        ambience=["ragefirechasm", "ragefire", "orgrimmar"],
        footstep="stone",
    ),
    "wailing-caverns": dict(
        map_name="wailingcaverns", ac_map=43, target_level=10,
        bosses=["Lady Anacondra", "Lord Cobrahn", "Kresh", "Lord Pythas",
                "Skum", "Lord Serpentis", "Verdan the Everliving"],
        # Mutanus is event-summoned (no static spawn); Verdan ends the run
        final_boss="Verdan the Everliving",
        ambience=["wailingcaverns", "wailingcavern", "barrens"],
        footstep="dirt",
    ),
    "shadowfang-keep": dict(
        map_name="shadowfang", ac_map=33, target_level=20,
        bosses=["Rethilgore", "Razorclaw the Butcher", "Baron Silverlaine",
                "Commander Springvale", "Odo the Blindwatcher",
                "Fenrus the Devourer", "Wolf Master Nandos",
                "Archmage Arugal", "Deathsworn Captain"],
        final_boss="Archmage Arugal",
        ambience=["shadowfangkeep", "shadowfang", "silverpine"],
        footstep="stone",
        # the keep's humans are undead: the Forsaken voice set, not a living
        # human's (there is no readable living-human set locally anyway)
        voices={3872: "scourge", 3873: "scourge", 3875: "scourge",
                3877: "scourge", 3887: "scourge", 4278: "scourge",
                4275: "scourge", 3850: "scourge"},
    ),
    # ---- the next six, configured from the data: bosses in AzerothCore's
    # instance_encounters order (the last is the final boss), target levels
    # from the D2-paced ladder in dungeons.gd. Untested until built.
    "blackfathom-deeps": dict(
        map_name="blackfathom", ac_map=48, target_level=23,
        bosses=["Ghamoo-ra", "Lady Sarevess", "Gelihast", "Lorgus Jett",
                "Old Serra'kis", "Twilight Lord Kelris", "Aku'mai"],
        final_boss="Aku'mai",
        ambience=["blackfathom", "ashenvale"],
        footstep="stone",
    ),
    "stockade": dict(
        map_name="stormwindjail", ac_map=34, target_level=26,
        bosses=["Targorr the Dread", "Kam Deepfury", "Hamhock", "Bazil Thredd",
                "Dextren Ward"],
        final_boss="Bazil Thredd",
        ambience=["stockade", "stormwind"],
        footstep="stone",
    ),
    "gnomeregan": dict(
        # the client no longer resolves this map by name; its WDT file id
        # was identified by the fact that all 404 spawns fall inside it
        map_name="gnomeraganinstance", wdt_fdid=782773, ac_map=90, target_level=31,
        bosses=["Viscous Fallout", "Electrocutioner 6000", "Crowd Pummeler 9-60",
                "Mekgineer Thermaplugg"],
        final_boss="Mekgineer Thermaplugg",
        ambience=["gnomeregan", "dunmorogh"],
        footstep="stone",
    ),
    "razorfen-kraul": dict(
        map_name="razorfenkraulinstance", ac_map=47, target_level=34,
        bosses=["Roogug", "Aggem Thorncurse", "Death Speaker Jargba",
                "Overlord Ramtusk", "Charlga Razorflank", "Agathelos the Raging"],
        final_boss="Charlga Razorflank",
        ambience=["razorfenkraul", "razorfen", "barrens"],
        footstep="dirt",
    ),
    "scarlet-monastery": dict(
        map_name="monasteryinstances", ac_map=189, target_level=40,
        bosses=["Interrogator Vishas", "Bloodmage Thalnos", "Houndmaster Loksey",
                "Arcanist Doan", "Herod", "High Inquisitor Fairbanks",
                "High Inquisitor Whitemane"],
        final_boss="High Inquisitor Whitemane",
        ambience=["scarletmonastery", "monastery", "tirisfal"],
        footstep="stone",
    ),
    "razorfen-downs": dict(
        map_name="razorfendowns", ac_map=129, target_level=47,
        bosses=["Mordresh Fire Eye", "Glutton", "Amnennar the Coldbringer"],
        final_boss="Amnennar the Coldbringer",
        ambience=["razorfendowns", "razorfen", "barrens"],
        footstep="dirt",
    ),
}
