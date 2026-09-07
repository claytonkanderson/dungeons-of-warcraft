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
    # Scarlet Monastery is four instances in WoW, four buildings stood apart
    # on one map, each with its own entrance trigger. `wing` names the
    # trigger ("Scarlet Monastery - <Wing> (Entrance)"); the build keeps the
    # building on that entrance's side of the map and everything near it.
    # The four together span one dungeon's worth of levels (34-40), so each
    # wing's XP budget (xp_span) is its share rather than the usual five.
    "scarlet-monastery-graveyard": dict(
        map_name="monasteryinstances", ac_map=189, wing="Graveyard",
        target_level=36, xp_span=2,
        bosses=["Interrogator Vishas", "Bloodmage Thalnos"],
        final_boss="Bloodmage Thalnos",
        ambience=["scarletmonastery", "monastery", "tirisfal"],
        footstep="stone",
    ),
    "scarlet-monastery-library": dict(
        map_name="monasteryinstances", ac_map=189, wing="Library",
        target_level=37, xp_span=1,
        bosses=["Houndmaster Loksey", "Arcanist Doan"],
        final_boss="Arcanist Doan",
        ambience=["scarletmonastery", "monastery", "tirisfal"],
        footstep="stone",
    ),
    "scarlet-monastery-armory": dict(
        map_name="monasteryinstances", ac_map=189, wing="Armory",
        target_level=39, xp_span=2,
        bosses=["Herod"],
        final_boss="Herod",
        ambience=["scarletmonastery", "monastery", "tirisfal"],
        footstep="stone",
    ),
    "scarlet-monastery-cathedral": dict(
        map_name="monasteryinstances", ac_map=189, wing="Cathedral",
        target_level=40, xp_span=1,
        bosses=["High Inquisitor Fairbanks", "Scarlet Commander Mograine",
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
    "uldaman": dict(
        map_name="uldaman", ac_map=70, target_level=50,
        bosses=["Revelosh", "Ironaya", "Obsidian Sentinel", "Ancient Stone Keeper",
                "Galgann Firehammer", "Grimlok", "Archaedas"],
        final_boss="Archaedas",
        ambience=["uldaman", "badlands"],
        footstep="stone",
    ),
    "zul-farrak": dict(
        map_name="tanarisinstance", ac_map=209, target_level=53,
        # Nekrum, Sezz'ziz and Gahz'rilla are summoned by scripted events in
        # WoW (the pyramid fight, the mallet) and have no spawn row
        bosses=["Antu'sul", "Theka the Martyr", "Witch Doctor Zum'rah",
                "Sergeant Bly", "Hydromancer Velratha", "Chief Ukorz Sandscalp"],
        final_boss="Chief Ukorz Sandscalp",
        ambience=["zulfarrak", "tanaris"],
        footstep="dirt",
    ),
    "maraudon": dict(
        map_name="mauradon", ac_map=349, target_level=56,
        bosses=["Noxxion", "Razorlash", "Lord Vyletongue", "Celebras the Cursed",
                "Landslide", "Tinkerer Gizlock", "Rotgrip", "Princess Theradras"],
        final_boss="Princess Theradras",
        ambience=["maraudon", "desolace"],
        footstep="dirt",
    ),
    "sunken-temple": dict(
        map_name="sunkentemple", ac_map=109, target_level=60,
        # the Avatar of Hakkar is summoned by the altar event: no spawn row
        bosses=["Atal'alarion", "Jammal'an the Prophet", "Ogom the Wretched",
                "Dreamscythe", "Weaver", "Morphaz", "Hazzas", "Shade of Eranikus"],
        final_boss="Shade of Eranikus",
        ambience=["sunkentemple", "swampofsorrows", "swamp"],
        footstep="stone",
    ),
    "blackrock-depths": dict(
        map_name="blackrockdepths", ac_map=230, target_level=63,
        # the Ring of Law arena bosses are event-spawned and have no rows
        bosses=["High Interrogator Gerstahn", "Lord Roccor", "Houndmaster Grebmar",
                "Pyromancer Loregrain", "Lord Incendius", "Warder Stilgiss", "Verek",
                "Fineous Darkvire", "Bael'Gar", "General Angerforge",
                "Golem Lord Argelmach", "Hurley Blackbreath", "Phalanx",
                "Ribbly Screwspigot", "Plugger Spazzring", "Ambassador Flamelash",
                "Panzor the Invincible", "Magmus", "Princess Moira Bronzebeard",
                "Emperor Dagran Thaurissan"],
        final_boss="Emperor Dagran Thaurissan",
        ambience=["blackrockdepths", "blackrock", "searinggorge"],
        footstep="stone",
    ),
    # Blackrock Spire is one building holding both instances; the lower one
    # is the western half (server x below 30), the upper spire the eastern.
    # `bounds` keeps the spawns and gameobjects of one side; `entrance`
    # names the trigger, as the map's first row is the exit
    "lower-blackrock-spire": dict(
        map_name="blackrockspire", ac_map=229, target_level=66,
        bounds={"xmax": 30.0},
        entrance="Searing Gorge Instance (Inside)",
        bosses=["Highlord Omokk", "Shadow Hunter Vosh'gajin", "War Master Voone",
                "Mother Smolderweb", "Quartermaster Zigris", "Halycon",
                "Bannok Grimaxe", "Crystal Fang", "Ghok Bashguud",
                "Overlord Wyrmthalak"],
        final_boss="Overlord Wyrmthalak",
        ambience=["blackrockspire", "blackrock", "burningsteppes"],
        footstep="stone",
    ),
    # Dire Maul: three instances in one building. Each wing is a quadrant of
    # the map in server coordinates (`bounds`); the wing's own entrance
    # trigger names the way in.
    "dire-maul-east": dict(
        map_name="diremaul", ac_map=429, target_level=67, xp_span=1,
        bounds={"ymax": -100.0},
        entrance="East Wing [West]",
        bosses=["Pusillin", "Zevrim Thornhoof", "Hydrospawn", "Lethtendris",
                "Alzzin the Wildshaper"],
        final_boss="Alzzin the Wildshaper",
        ambience=["diremaul", "feralas"],
        footstep="stone",
    ),
    "dire-maul-west": dict(
        map_name="diremaul", ac_map=429, target_level=68, xp_span=1,
        bounds={"xmax": 250.0, "ymin": 150.0},
        entrance="West Wing [North]",
        bosses=["Tendris Warpwood", "Illyanna Ravenoak", "Magister Kalendris",
                "Tsu'zee", "Immol'thar", "Prince Tortheldrin"],
        final_boss="Prince Tortheldrin",
        ambience=["diremaul", "feralas"],
        footstep="stone",
    ),
    "dire-maul-north": dict(
        map_name="diremaul", ac_map=429, target_level=69, xp_span=1,
        bounds={"xmin": 250.0, "ymin": -100.0},
        entrance="North Wing (Entrance)",
        bosses=["Guard Mol'dar", "Stomper Kreeg", "Guard Fengus", "Guard Slip'kik",
                "Captain Kromcrush", "Cho'Rush the Observer", "King Gordok"],
        final_boss="King Gordok",
        ambience=["diremaul", "feralas"],
        footstep="stone",
    ),
    "scholomance": dict(
        map_name="schoolofnecromancy", ac_map=289, target_level=72,
        # Kirtonos is summoned by the blood of innocents: no spawn row
        bosses=["Jandice Barov", "Rattlegore", "Marduk Blackpool", "Vectus",
                "Ras Frostwhisper", "Instructor Malicia", "Doctor Theolen Krastinov",
                "Lorekeeper Polkelt", "The Ravenian", "Lord Alexei Barov",
                "Lady Illucia Barov", "Darkmaster Gandling"],
        final_boss="Darkmaster Gandling",
        ambience=["scholomance", "westernplaguelands", "plaguelands"],
        footstep="stone",
    ),
    "stratholme": dict(
        map_name="stratholme", ac_map=329, target_level=75,
        bosses=["The Unforgiven", "Timmy the Cruel", "Malor the Zealous",
                "Cannon Master Willey", "Archivist Galford", "Grand Crusader Dathrohan",
                "Baroness Anastari", "Nerub'enkan", "Maleki the Pallid",
                "Magistrate Barthilas", "Hearthsinger Forresten",   # Ramstein is event-summoned
                "Stonespine", "Baron Rivendare"],
        final_boss="Baron Rivendare",
        ambience=["stratholme", "easternplaguelands", "plaguelands"],
        footstep="stone",
    ),
    # the eastern half of the Blackrock Spire building (see lower-blackrock-spire)
    "upper-blackrock-spire": dict(
        map_name="blackrockspire", ac_map=229, target_level=78,
        bounds={"xmin": 30.0},
        entrance="Searing Gorge Instance (Inside)",
        bosses=["Pyroguard Emberseer", "Goraluk Anvilcrack", "Jed Runewatcher",
                "Warchief Rend Blackhand", "The Beast", "General Drakkisath"],
        final_boss="General Drakkisath",
        ambience=["blackrockspire", "blackrock", "burningsteppes"],
        footstep="stone",
    ),
    # the two raids, at the top of the ladder
    "molten-core": dict(
        map_name="moltencore", ac_map=409, target_level=82,
        entrance="Window Entrance",
        bosses=["Lucifron", "Magmadar", "Gehennas", "Garr", "Baron Geddon",
                "Shazzrah", "Sulfuron Harbinger", "Golemagg the Incinerator",
                "Majordomo Executus", "Ragnaros"],
        final_boss="Ragnaros",
        # Majordomo and Ragnaros are summoned by the rune event and have no
        # spawn rows: placed where AzerothCore's scripts summon them
        # (boss_majordomo_executus.cpp: MajordomoSummonPos, RagnarosSummonPos)
        extra_spawns=[("Majordomo Executus", 759.542, -1173.43, -118.974, 3.3048),
                      ("Ragnaros", 838.3082, -831.4665, -232.1853, 2.199115)],
        ambience=["moltencore", "blackrock", "lava"],
        footstep="stone",
    ),
    "blackwing-lair": dict(
        map_name="blackwinglair", ac_map=469, target_level=86,
        bosses=["Razorgore the Untamed", "Vaelastrasz the Corrupt",
                "Broodlord Lashlayer", "Firemaw", "Ebonroc", "Flamegor",
                "Chromaggus", "Nefarian"],
        final_boss="Nefarian",
        # Nefarian flies in from outside in WoW (boss_nefarian.cpp spawns him
        # 300 m away); he stands on his throne-room floor here, between the
        # points his Shadowblink script uses, a little above it to settle
        extra_spawns=[("Nefarian", -7556.0, -1231.0, 478.0, 1.8)],
        ambience=["blackwinglair", "blackrock", "lava"],
        footstep="stone",
    ),
}
