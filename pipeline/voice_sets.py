"""Creature voice sets beyond the Deadmines four: file paths per family and
role, every one confirmed readable in the local client.

GENERATED — do not hand-edit. Regenerate by re-running the probe that
wrote it (scratchpad/voice_emit.py in the session that added this: it
enumerates <stem><role><suffix>.ogg under sound/creature and
sound/character and keeps what CASC can actually read). Families are
keyed by the names used in build_creatures.VOICE_BY_MODEL and
dungeon_config voices=; build_audio merges this into CREATURE_SFX."""

VOICE_SETS = {
    "worgen": {
        "aggro": [
            "sound/creature/worgen/mworgenaggroa.ogg",
        ],
        "attack": [
            "sound/creature/worgen/mworgenattacka.ogg",
            "sound/creature/worgen/mworgenattackb.ogg",
            "sound/creature/worgen/mworgenattackc.ogg",
            "sound/creature/worgen/mworgenattackd.ogg",
        ],
        "wound": [
            "sound/creature/worgen/mworgenwounda.ogg",
            "sound/creature/worgen/mworgenwoundb.ogg",
            "sound/creature/worgen/mworgenwoundc.ogg",
        ],
        "death": [
            "sound/creature/worgen/mworgendeatha.ogg",
        ],
    },
    "wolf": {
        "aggro": [
            "sound/creature/wolf/mwolfaggro1.ogg",
            "sound/creature/wolf/mwolfaggro2.ogg",
            "sound/creature/wolf/mwolfaggro3.ogg",
        ],
        "attack": [
            "sound/creature/wolf/mwolfattack1.ogg",
            "sound/creature/wolf/mwolfattack2.ogg",
            "sound/creature/wolf/mwolfattack3.ogg",
            "sound/creature/wolf/mwolfattack4.ogg",
        ],
        "wound": [
            "sound/creature/wolf/mwolfwound1.ogg",
            "sound/creature/wolf/mwolfwound2.ogg",
            "sound/creature/wolf/mwolfwound3.ogg",
            "sound/creature/wolf/mwolfwound4.ogg",
        ],
        "death": [
            "sound/creature/wolf/mwolfdeath1.ogg",
        ],
    },
    "bat": {
        "aggro": [
            "sound/creature/felbat/felbataggro.ogg",
        ],
        "attack": [
            "sound/creature/felbat/felbatattacka.ogg",
            "sound/creature/felbat/felbatattackb.ogg",
            "sound/creature/felbat/felbatattackc.ogg",
        ],
        "wound": [
            "sound/creature/felbat/felbatwounda.ogg",
            "sound/creature/felbat/felbatwoundb.ogg",
        ],
        "death": [
            "sound/creature/felbat/felbatdeath.ogg",
        ],
    },
    "ghost": {
        "aggro": [
            "sound/creature/ghost/ghostaggroa.ogg",
        ],
        "attack": [
            "sound/creature/ghost/ghostattacka.ogg",
            "sound/creature/ghost/ghostattackb.ogg",
            "sound/creature/ghost/ghostattackc.ogg",
        ],
        "wound": [
            "sound/creature/ghost/ghostwounda.ogg",
            "sound/creature/ghost/ghostwoundb.ogg",
            "sound/creature/ghost/ghostwoundc.ogg",
        ],
        "death": [
            "sound/creature/ghost/ghostdeatha.ogg",
        ],
    },
    "horse": {
        "aggro": [
            "sound/creature/horse/mhorseaggroa.ogg",
        ],
        "attack": [
            "sound/creature/horse/mhorseattacka.ogg",
            "sound/creature/horse/mhorseattackb.ogg",
            "sound/creature/horse/mhorseattackc.ogg",
        ],
        "wound": [
            "sound/creature/horse/mhorsewounda.ogg",
            "sound/creature/horse/mhorsewoundb.ogg",
            "sound/creature/horse/mhorsewoundc.ogg",
        ],
        "death": [
            "sound/creature/horse/mhorsedeatha.ogg",
        ],
    },
    "raptor": {
        "aggro": [
            "sound/creature/raptor/mraptoraggroa.ogg",
        ],
        "attack": [
            "sound/creature/raptor/mraptorattacka.ogg",
            "sound/creature/raptor/mraptorattackb.ogg",
            "sound/creature/raptor/mraptorattackc.ogg",
        ],
        "wound": [
            "sound/creature/raptor/mraptorwounda.ogg",
            "sound/creature/raptor/mraptorwoundb.ogg",
            "sound/creature/raptor/mraptorwoundc.ogg",
        ],
        "death": [
            "sound/creature/raptor/mraptordeatha.ogg",
        ],
    },
    "snake": {
        "wound": [
            "sound/creature/snake/snakewound.ogg",
        ],
        "death": [
            "sound/creature/snake/snakedeath.ogg",
        ],
    },
    "satyr": {
        "aggro": [
            "sound/creature/satyr/satyraggroa.ogg",
        ],
        "attack": [
            "sound/creature/satyr/satyrattacka.ogg",
            "sound/creature/satyr/satyrattackb.ogg",
            "sound/creature/satyr/satyrattackc.ogg",
        ],
        "wound": [
            "sound/creature/satyr/satyrwounda.ogg",
            "sound/creature/satyr/satyrwoundb.ogg",
            "sound/creature/satyr/satyrwoundc.ogg",
        ],
        "death": [
            "sound/creature/satyr/satyrdeatha.ogg",
        ],
    },
    "rat": {
        "wound": [
            "sound/creature/rat/ratwounda.ogg",
        ],
        "death": [
            "sound/creature/rat/ratdeatha.ogg",
        ],
    },
    "lasher": {
        "aggro": [
            "sound/creature/lasher/lasheraggro.ogg",
        ],
        "attack": [
            "sound/creature/lasher/lasherattacka.ogg",
            "sound/creature/lasher/lasherattackb.ogg",
            "sound/creature/lasher/lasherattackc.ogg",
        ],
        "wound": [
            "sound/creature/lasher/lasherwounda.ogg",
            "sound/creature/lasher/lasherwoundb.ogg",
            "sound/creature/lasher/lasherwoundc.ogg",
        ],
        "death": [
            "sound/creature/lasher/lasherdeath.ogg",
        ],
    },
    "bogbeast": {
        "aggro": [
            "sound/creature/bogbeast/mbogbeastaggroa.ogg",
        ],
        "attack": [
            "sound/creature/bogbeast/mbogbeastattack2a.ogg",
            "sound/creature/bogbeast/mbogbeastattack2b.ogg",
        ],
        "wound": [
            "sound/creature/bogbeast/mbogbeastwounda.ogg",
            "sound/creature/bogbeast/mbogbeastwoundb.ogg",
            "sound/creature/bogbeast/mbogbeastwoundc.ogg",
        ],
        "death": [
            "sound/creature/bogbeast/mbogbeastdeatha.ogg",
        ],
    },
    "skeleton": {
        "aggro": [
            "sound/creature/skeletonmage/skeletonmageaggro.ogg",
        ],
        "attack": [
            "sound/creature/skeletonmage/skeletonmageattacka.ogg",
            "sound/creature/skeletonmage/skeletonmageattackb.ogg",
            "sound/creature/skeletonmage/skeletonmageattackc.ogg",
        ],
        "wound": [
            "sound/creature/skeletonmage/skeletonmagewounda.ogg",
            "sound/creature/skeletonmage/skeletonmagewoundb.ogg",
            "sound/creature/skeletonmage/skeletonmagewoundc.ogg",
        ],
        "death": [
            "sound/creature/skeletonmage/skeletonmagedeatha.ogg",
        ],
    },
    "seaturtle": {
        "aggro": [
            "sound/creature/seaturtle/seaturtleaggroa.ogg",
        ],
        "attack": [
            "sound/creature/seaturtle/seaturtleattacka.ogg",
            "sound/creature/seaturtle/seaturtleattackb.ogg",
            "sound/creature/seaturtle/seaturtleattackc.ogg",
        ],
        "wound": [
            "sound/creature/seaturtle/seaturtlewounda.ogg",
            "sound/creature/seaturtle/seaturtlewoundb.ogg",
            "sound/creature/seaturtle/seaturtlewoundc.ogg",
            "sound/creature/seaturtle/seaturtlewoundd.ogg",
        ],
        "death": [
            "sound/creature/seaturtle/seaturtledeatha.ogg",
        ],
    },
    "faeriedragon": {
        "aggro": [
            "sound/creature/faeriedragon/faeriedragonaggroa.ogg",
        ],
        "attack": [
            "sound/creature/faeriedragon/faeriedragonattacka.ogg",
            "sound/creature/faeriedragon/faeriedragonattackb.ogg",
            "sound/creature/faeriedragon/faeriedragonattackc.ogg",
        ],
        "wound": [
            "sound/creature/faeriedragon/faeriedragonwounda.ogg",
            "sound/creature/faeriedragon/faeriedragonwoundb.ogg",
            "sound/creature/faeriedragon/faeriedragonwoundc.ogg",
        ],
        "death": [
            "sound/creature/faeriedragon/faeriedragondeatha.ogg",
        ],
    },
    "thunderlizard": {
        "aggro": [
            "sound/creature/thunderlizard/thunderlizardaggroa.ogg",
        ],
        "attack": [
            "sound/creature/thunderlizard/thunderlizardattacka.ogg",
            "sound/creature/thunderlizard/thunderlizardattackb.ogg",
            "sound/creature/thunderlizard/thunderlizardattackc.ogg",
        ],
        "wound": [
            "sound/creature/thunderlizard/thunderlizardwounda.ogg",
            "sound/creature/thunderlizard/thunderlizardwoundb.ogg",
            "sound/creature/thunderlizard/thunderlizardwoundc.ogg",
        ],
        "death": [
            "sound/creature/thunderlizard/thunderlizarddeatha.ogg",
        ],
    },
    "frog": {
        "wound": [
            "sound/creature/frog/frogwounda.ogg",
        ],
        "death": [
            "sound/creature/frog/frogdeatha.ogg",
        ],
    },
    "orc": {
        "attack": [
            "sound/character/orc/orcmale/orcmaleattacka.ogg",
            "sound/character/orc/orcmale/orcmaleattackb.ogg",
            "sound/character/orc/orcmale/orcmaleattackc.ogg",
            "sound/character/orc/orcmale/orcmaleattackd.ogg",
        ],
        "wound": [
            "sound/character/orc/orcmale/orcmalewounda.ogg",
            "sound/character/orc/orcmale/orcmalewoundb.ogg",
            "sound/character/orc/orcmale/orcmalewoundc.ogg",
        ],
        "death": [
            "sound/character/orc/orcmale/orcmaledeath.ogg",
        ],
    },
    "nightelf": {
        "attack": [
            "sound/character/nightelf/nightelfmale/nightelfmaleattacka.ogg",
            "sound/character/nightelf/nightelfmale/nightelfmaleattackb.ogg",
            "sound/character/nightelf/nightelfmale/nightelfmaleattackc.ogg",
        ],
        "wound": [
            "sound/character/nightelf/nightelfmale/nightelfmalewounda.ogg",
            "sound/character/nightelf/nightelfmale/nightelfmalewoundb.ogg",
            "sound/character/nightelf/nightelfmale/nightelfmalewoundc.ogg",
        ],
        "death": [
            "sound/character/nightelf/nightelfmale/nightelfmaledeatha.ogg",
        ],
    },
    "tauren": {
        "attack": [
            "sound/character/tauren/taurenmale/taurenmaleattacka.ogg",
            "sound/character/tauren/taurenmale/taurenmaleattackb.ogg",
            "sound/character/tauren/taurenmale/taurenmaleattackc.ogg",
            "sound/character/tauren/taurenmale/taurenmaleattackd.ogg",
        ],
        "wound": [
            "sound/character/tauren/taurenmale/taurenmalewounda.ogg",
            "sound/character/tauren/taurenmale/taurenmalewoundb.ogg",
            "sound/character/tauren/taurenmale/taurenmalewoundc.ogg",
        ],
        "death": [
            "sound/character/tauren/taurenmale/taurenmaledeatha.ogg",
        ],
    },
    "scourge": {
        "attack": [
            "sound/character/scourge/scourgemale/scourgemaleattacka.ogg",
            "sound/character/scourge/scourgemale/scourgemaleattackb.ogg",
            "sound/character/scourge/scourgemale/scourgemaleattackc.ogg",
            "sound/character/scourge/scourgemale/scourgemaleattackd.ogg",
        ],
        "wound": [
            "sound/character/scourge/scourgemale/scourgemalewounda.ogg",
            "sound/character/scourge/scourgemale/scourgemalewoundb.ogg",
            "sound/character/scourge/scourgemale/scourgemalewoundc.ogg",
        ],
        "death": [
            "sound/character/scourge/scourgemale/scourgemaledeatha.ogg",
            "sound/character/scourge/scourgemale/scourgemaledeathb.ogg",
        ],
    },
    "dwarf": {
        "attack": [
            "sound/character/dwarf/dwarfmale/dwarfmaleattacka.ogg",
            "sound/character/dwarf/dwarfmale/dwarfmaleattackb.ogg",
            "sound/character/dwarf/dwarfmale/dwarfmaleattackc.ogg",
            "sound/character/dwarf/dwarfmale/dwarfmaleattackd.ogg",
        ],
        "wound": [
            "sound/character/dwarf/dwarfmale/dwarfmalewounda.ogg",
            "sound/character/dwarf/dwarfmale/dwarfmalewoundb.ogg",
            "sound/character/dwarf/dwarfmale/dwarfmalewoundc.ogg",
        ],
        "death": [
            "sound/character/dwarf/dwarfmale/dwarfmaledeatha.ogg",
        ],
    },
}
