"""Recon pass 4: WMO root inventories + unique doodads/props, local checks."""
import struct
from casc import Storage, CascError

s = Storage(verbose=False)


def parse(buf):
    out = {}
    p = 0
    while p + 8 <= len(buf):
        cid = buf[p:p + 4][::-1]
        size = int.from_bytes(buf[p + 4:p + 8], "little")
        out.setdefault(cid, []).append(buf[p + 8:p + 8 + size])
        p += 8 + size
    return out


def check_local(fdids):
    miss = []
    for f in fdids:
        try:
            s.read_fdid(f)
        except (CascError, KeyError):
            miss.append(f)
    return miss


for wmo_fdid in (108483, 108538, 113966, 113970, 114107, 114109):
    root = parse(s.read_fdid(wmo_fdid))
    mohd = root[b"MOHD"][0]
    (ntex, ngroups, nport, nlight, ndn, ndd, nds) = \
        struct.unpack_from("<7I", mohd, 0)
    names = root.get(b"MOGN", [b""])[0]
    sample = [n.decode("ascii", "?") for n in names.split(b"\0") if n][:6]
    gfid = struct.unpack(f"<{len(root[b'GFID'][0])//4}I", root[b"GFID"][0]) \
        if b"GFID" in root else ()
    modi = struct.unpack(f"<{len(root[b'MODI'][0])//4}I", root[b"MODI"][0]) \
        if b"MODI" in root else ()
    uniq_dood = sorted(set(x for x in modi if x))
    miss_g = check_local([f for f in gfid if f])
    miss_d = check_local(uniq_dood)
    has_liq = b"MLIQ" in root
    print(f"WMO {wmo_fdid}: groups={ngroups} materials={ntex} portals={nport} "
          f"lights={nlight} doodadDefs={ndd} sets={nds} "
          f"uniqueDoodadModels={len(uniq_dood)}")
    print(f"   group names: {sample}")
    print(f"   missing group files: {len(miss_g)}  missing doodads: {len(miss_d)}")
    if b"MODS" in root:
        ds = root[b"MODS"][0]
        for i in range(len(ds) // 32):
            nm = ds[i*32:i*32+20].rstrip(b"\0").decode("ascii", "?")
            st, cnt = struct.unpack_from("<II", ds, i*32+20)
            print(f"   set {i}: {nm!r} start={st} n={cnt}")

# unique M2 props across all tiles (MDDF references MMID/MMDX or fdids)
wdt = s.read_fdid(780605)
w = parse(wdt)
main, maid = w[b"MAIN"][0], w[b"MAID"][0]
uniq = set()
total = 0
for i in range(64 * 64):
    if not int.from_bytes(main[i*8:i*8+4], "little") & 1:
        continue
    e = struct.unpack_from("<8I", maid, i * 32)
    oc = parse(s.read_fdid(e[1]))
    mddf = oc.get(b"MDDF", [b""])[0]
    for k in range(len(mddf) // 36):
        nid = int.from_bytes(mddf[k*36:k*36+4], "little")
        flags = int.from_bytes(mddf[k*36+34:k*36+36], "little")
        uniq.add(nid)
        total += 1
print(f"\ntile props: {total} placements, {len(uniq)} unique models")
print("missing locally:", len(check_local(sorted(uniq))))

# one terrain sanity check: height variance of tile 33,31 (dungeon center)
i = 31 * 64 + 33
e = struct.unpack_from("<8I", maid, i * 32)
rc = parse(s.read_fdid(e[0]))
hts = []
for c in rc.get(b"MCNK", []):
    sub = parse(c[128:])
    if b"MCVT" in sub:
        hts += list(struct.unpack("<145f", sub[b"MCVT"][0][:580]))
if hts:
    print(f"terrain heights tile 33,31: min={min(hts):.1f} max={max(hts):.1f}")
