"""Export D2 set bonuses -> assets/items/setbonus.json.

Piggybacks on the D2_Billboard pipeline (tbl strings + MPQ reader) since the
existing setitems.json carries membership but not bonuses.

  items: set-item name -> [ [props@2 worn], [props@3], [props@4], [props@5] ]
         (SetItems.txt aprop1..5 pairs; index i activates at i+2 pieces)
  sets:  set name -> {"partial": [ [props@2], [props@3], [props@4], [props@5] ],
                      "full": [props], "count": total pieces}
"""
import json
import sys
from pathlib import Path

sys.path.insert(0, r"D:\tree\D2_Billboard\pipeline")
import tbl                        # noqa: E402
from sprites import mpqs          # noqa: E402
from export_affixes import read_table, g, Resolver  # noqa: E402

OUT = Path(__file__).resolve().parent.parent / "assets" / "items"


def pair_props(r, prefix_fmt, thresholds):
    """[[props for each threshold]] from <P>a/<P>b column pairs."""
    out = []
    for t in thresholds:
        plist = []
        for half in ("a", "b"):
            code = g(r, f"{prefix_fmt}{t}{half}").strip()
            if not code:
                continue
            plist.append({"code": code,
                          "param": g(r, f"{prefix_fmt.replace('Code', 'Param').replace('prop', 'par')}{t}{half}"),
                          "min": g(r, f"{prefix_fmt.replace('Code', 'Min').replace('prop', 'min')}{t}{half}"),
                          "max": g(r, f"{prefix_fmt.replace('Code', 'Max').replace('prop', 'max')}{t}{half}")})
        out.append(plist)
    return out


def main():
    strings = tbl.load(mpqs())
    res = Resolver(strings)

    setnames = {}
    sets = {}
    for r in read_table("Sets.txt"):
        sid = g(r, "index").strip()
        if not sid:
            continue
        name = res(g(r, "name") or sid)
        setnames[sid] = name
        full = []
        for i in range(1, 9):
            code = g(r, f"FCode{i}").strip()
            if not code:
                continue
            full.append({"code": code, "param": g(r, f"FParam{i}"),
                         "min": g(r, f"FMin{i}"), "max": g(r, f"FMax{i}")})
        sets[name] = {"partial": pair_props(r, "PCode", (2, 3, 4, 5)),
                      "full": full, "count": 0}

    items = {}
    for r in read_table("SetItems.txt"):
        iname = res(g(r, "index").strip())
        sid = g(r, "set").strip()
        if not iname or not sid:
            continue
        sname = setnames.get(sid, sid)
        if sname in sets:
            sets[sname]["count"] += 1
        aprops = pair_props(r, "aprop", (1, 2, 3, 4, 5))
        if any(aprops):
            items[iname] = aprops

    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "setbonus.json").write_text(json.dumps(
        {"items": items, "sets": sets}, separators=(",", ":")))
    n_partial = sum(1 for s in sets.values() if any(s["partial"]))
    print(f"setbonus.json: {len(items)} items with aprops, {len(sets)} sets "
          f"({n_partial} with partial, "
          f"{sum(1 for s in sets.values() if s['full'])} with full bonuses)")


if __name__ == "__main__":
    main()
