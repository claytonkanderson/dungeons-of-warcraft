"""Read-only access to a local CASC (TACT) storage.

Resolves: name hash or FileDataID -> ckey (root) -> ekey (encoding)
-> archive location (.idx) -> BLTE-decoded bytes (data.###).

Pure Python, stdlib only. Verified against the shared storage in
D:\\Games\\World of Warcraft\\Data (wow_anniversary / wow_classic_era).
"""
import struct
import zlib
from pathlib import Path

from config import DATA_DIR, WOW_ROOT, PRODUCT


class CascError(RuntimeError):
    pass


# ---------------------------------------------------------------- lz4 block
def lz4_block_decompress(src: bytes, decomp_size: int) -> bytes:
    out = bytearray()
    i, n = 0, len(src)
    while i < n:
        token = src[i]; i += 1
        lit = token >> 4
        if lit == 15:
            while True:
                x = src[i]; i += 1
                lit += x
                if x != 255:
                    break
        out += src[i:i + lit]
        i += lit
        if i >= n:
            break  # last sequence has no match part
        offset = src[i] | (src[i + 1] << 8); i += 2
        mlen = (token & 0xF) + 4
        if (token & 0xF) == 15:
            while True:
                x = src[i]; i += 1
                mlen += x
                if x != 255:
                    break
        start = len(out) - offset
        for k in range(mlen):  # byte-wise: matches may overlap themselves
            out.append(out[start + k])
    if len(out) != decomp_size:
        raise CascError(f"lz4: got {len(out)} bytes, wanted {decomp_size}")
    return bytes(out)


# ------------------------------------------------------------------- BLTE
def blte_decode(buf: bytes) -> bytes:
    if buf[:4] != b"BLTE":
        raise CascError("not a BLTE blob")
    header_size = int.from_bytes(buf[4:8], "big")
    chunks = []
    if header_size == 0:
        chunks.append((len(buf) - 8, None, buf[8:]))
    else:
        flags = buf[8]
        count = int.from_bytes(buf[9:12], "big")
        if flags != 0xF or count == 0:
            raise CascError(f"odd BLTE table: flags={flags:#x} count={count}")
        pos = 12
        offs = header_size
        for _ in range(count):
            csize = int.from_bytes(buf[pos:pos + 4], "big")
            dsize = int.from_bytes(buf[pos + 4:pos + 8], "big")
            pos += 24  # skip md5
            chunks.append((csize, dsize, buf[offs:offs + csize]))
            offs += csize
    out = bytearray()
    for csize, dsize, data in chunks:
        mode = data[0:1]
        body = data[1:]
        if mode == b"N":
            out += body
        elif mode == b"Z":
            out += zlib.decompress(body)
        elif mode == b"4":
            out += lz4_block_decompress(body, dsize)
        elif mode == b"F":
            out += blte_decode(body)
        elif mode == b"E":
            raise CascError("encrypted BLTE chunk (no TACT key support)")
        else:
            raise CascError(f"unknown BLTE mode {mode!r}")
    return bytes(out)


# -------------------------------------------------------------- build info
def read_build_info(product: str) -> dict:
    text = (WOW_ROOT / ".build.info").read_text(encoding="utf-8")
    lines = [l for l in text.splitlines() if l.strip()]
    headers = [h.split("!")[0] for h in lines[0].split("|")]
    for line in lines[1:]:
        row = dict(zip(headers, line.split("|")))
        if row.get("Product") == product:
            return row
    raise CascError(f"product {product} not in .build.info")


def read_config(hash_hex: str) -> dict:
    p = DATA_DIR / "config" / hash_hex[:2] / hash_hex[2:4] / hash_hex
    cfg = {}
    for line in p.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        k, _, v = line.partition("=")
        cfg[k.strip()] = v.strip()
    return cfg


# ---------------------------------------------------------------- indices
def _bucket_of(ekey9: bytes) -> int:
    x = 0
    for byte in ekey9:
        x ^= byte
    return (x & 0xF) ^ (x >> 4)


def load_indices() -> dict:
    """ekey 9-byte prefix -> (archive_no, offset, size)"""
    newest = {}
    for p in (DATA_DIR / "data").glob("*.idx"):
        bucket = int(p.name[:2], 16)
        version = int(p.name[2:10], 16)
        if bucket not in newest or version > newest[bucket][0]:
            newest[bucket] = (version, p)
    table = {}
    for bucket, (_, p) in sorted(newest.items()):
        raw = p.read_bytes()
        header_size = int.from_bytes(raw[0:4], "little")
        data_start = 8 + header_size
        data_start = (data_start + 0xF) & ~0xF  # align 16
        entries_size = int.from_bytes(raw[data_start:data_start + 4], "little")
        pos = data_start + 8
        end = pos + entries_size
        if entries_size % 18 or end > len(raw):
            raise CascError(f"{p.name}: bad entry block ({entries_size})")
        while pos < end:
            ekey = raw[pos:pos + 9]
            if ekey != b"\x00" * 9:
                iv = int.from_bytes(raw[pos + 9:pos + 14], "big")
                size = int.from_bytes(raw[pos + 14:pos + 18], "little")
                table[ekey] = (iv >> 30, iv & 0x3FFFFFFF, size)
            pos += 18
    return table


def read_from_archives(loc, verify_bucket=True) -> bytes:
    archive, offset, size = loc
    p = DATA_DIR / "data" / f"data.{archive:03d}"
    with open(p, "rb") as f:
        f.seek(offset)
        blob = f.read(size)
    # 30-byte per-file header: reversed ekey16, u32 size, u16 flags, 2 crcs
    if blob[30:34] == b"BLTE":
        return blte_decode(blob[30:])
    if blob[:4] == b"BLTE":  # storages with headerless entries
        return blte_decode(blob)
    raise CascError(f"no BLTE at data.{archive:03d}+{offset:#x}")


# --------------------------------------------------------------- encoding
def parse_encoding(buf: bytes) -> dict:
    """ckey -> first ekey"""
    if buf[:2] != b"EN":
        raise CascError("bad encoding magic")
    version, ckey_len, ekey_len = buf[2], buf[3], buf[4]
    cpage_kb = int.from_bytes(buf[5:7], "big")
    epage_kb = int.from_bytes(buf[7:9], "big")
    cpage_count = int.from_bytes(buf[9:13], "big")
    int.from_bytes(buf[13:17], "big")  # ekey spec page count (unused)
    espec_size = int.from_bytes(buf[18:22], "big")
    pos = 22 + espec_size
    pos += cpage_count * 32  # page index: first-ckey + md5 per page
    page_size = cpage_kb * 1024
    table = {}
    for _ in range(cpage_count):
        page = buf[pos:pos + page_size]
        pos += page_size
        p = 0
        while p + 6 + ckey_len + ekey_len <= len(page):
            key_count = page[p]
            if key_count == 0:
                break
            ckey = page[p + 6:p + 6 + ckey_len]
            ekey = page[p + 6 + ckey_len:p + 6 + ckey_len + ekey_len]
            table[ckey] = ekey
            p += 6 + ckey_len + key_count * ekey_len
    return table


# ------------------------------------------------------------------- root
class Root:
    def __init__(self, by_fdid, by_hash):
        self.by_fdid = by_fdid      # fdid -> ckey
        self.by_hash = by_hash      # jenkins96 -> fdid

    def fdid_for_path(self, path):
        from jenkins import path_hash
        return self.by_hash.get(path_hash(path))


LOCALE_ENUS = 0x2
CF_NO_NAME_HASH = 0x10000000


def parse_root(buf: bytes) -> Root:
    if buf[:4] != b"TSFM":
        raise CascError("interleaved (pre-8.2) root not supported")
    u = lambda o: int.from_bytes(buf[o:o + 4], "little")
    if u(4) in range(0x10, 0x40) and u(8) in (1, 2, 3, 4):
        header_size, version = u(4), u(8)
        total_files, named_files = u(12), u(16)
        pos = header_size
    else:
        version = 1
        total_files, named_files = u(4), u(8)
        pos = 12
    by_fdid, by_hash = {}, {}
    n = len(buf)
    while pos + 12 <= n:
        if version >= 2:
            # Empirically determined (brute-force tiled against this build):
            # {u32 numFiles, u32 unk, u32 flagsA, u32 flagsB, u8 unk} = 17B,
            # then [i32 fdid deltas][ckeys 16B][name hashes 8B].
            # Every block in this storage carries name hashes (the global
            # header's named == total); refuse storages where that breaks.
            if total_files != named_files:
                raise CascError("v2 root with unnamed blocks: layout of the "
                                "no-name-hash flag is unverified here")
            num = u(pos)
            has_hashes = True
            pos += 17
        else:
            num = u(pos)
            cf = u(pos + 4)
            has_hashes = not (cf & CF_NO_NAME_HASH)
            pos += 12
        fdids = []
        cur = -1
        for i in range(num):
            cur += struct.unpack_from("<i", buf, pos + 4 * i)[0] + 1
            fdids.append(cur)
        pos += 4 * num
        ckeys_off = pos
        pos += 16 * num
        hashes_off = None
        if has_hashes:
            hashes_off = pos
            pos += 8 * num
        for i in range(num):
            fdid = fdids[i]
            if fdid not in by_fdid:
                by_fdid[fdid] = buf[ckeys_off + 16 * i: ckeys_off + 16 * i + 16]
            if hashes_off is not None:
                h = int.from_bytes(buf[hashes_off + 8 * i: hashes_off + 8 * i + 8], "little")
                by_hash.setdefault(h, fdid)
    return Root(by_fdid, by_hash)


# ---------------------------------------------------------------- storage
class Storage:
    def __init__(self, product=PRODUCT, verbose=True):
        info = read_build_info(product)
        self.version = info.get("Version", "?")
        bc = read_config(info["Build Key"])
        self.log = print if verbose else (lambda *a, **k: None)
        self.log(f"[casc] {product} {self.version}")
        self.index = load_indices()
        self.log(f"[casc] {len(self.index)} local archive entries")
        enc_keys = bc["encoding"].split()
        enc_blob = self._read_ekey(bytes.fromhex(enc_keys[1]))
        self.encoding = parse_encoding(enc_blob)
        self.log(f"[casc] encoding: {len(self.encoding)} ckeys")
        root_ckey = bytes.fromhex(bc["root"].split()[0])
        self.root = parse_root(self.read_ckey(root_ckey))
        self.log(f"[casc] root: {len(self.root.by_fdid)} files, "
                 f"{len(self.root.by_hash)} named")

    def _read_ekey(self, ekey: bytes) -> bytes:
        loc = self.index.get(ekey[:9])
        if loc is None:
            raise CascError(f"ekey {ekey.hex()} not in local storage")
        return read_from_archives(loc)

    def read_ckey(self, ckey: bytes) -> bytes:
        ekey = self.encoding.get(ckey)
        if ekey is None:
            raise CascError(f"ckey {ckey.hex()} not in encoding")
        return self._read_ekey(ekey)

    def read_fdid(self, fdid: int) -> bytes:
        ckey = self.root.by_fdid.get(fdid)
        if ckey is None:
            raise CascError(f"fdid {fdid} not in root")
        return self.read_ckey(ckey)

    def read_path(self, path: str) -> bytes:
        fdid = self.root.fdid_for_path(path)
        if fdid is None:
            raise CascError(f"path not in root: {path}")
        return self.read_fdid(fdid)


if __name__ == "__main__":
    import sys
    s = Storage()
    for path in sys.argv[1:] or [r"creature\edwinvancleef\edwinvancleef.m2"]:
        fdid = s.root.fdid_for_path(path)
        print(f"{path}: fdid={fdid}", end=" ")
        if fdid is None:
            print("(name not in root)")
            continue
        try:
            data = s.read_fdid(fdid)
            print(f"-> {len(data)} bytes, magic={data[:4]!r}")
        except CascError as e:
            print(f"-> NOT LOCAL: {e}")
