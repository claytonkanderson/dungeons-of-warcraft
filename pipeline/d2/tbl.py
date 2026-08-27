"""Diablo II .tbl string table parser.

Layout (verified against the LoD tables in these archives):
  21-byte header:
    u16 CRC, u16 NumElements, u32 HashTableSize, u8 Version,
    u32 StringOffset, u32 MaxTries, u32 FileSize
    (StringOffset == 21 + 2*NumElements + 17*HashTableSize on every file here)
  NumElements x u16 indices (not needed for a full dump)
  HashTableSize x 17-byte hash entries:
    u8 used, u16 index, u32 hash, u32 keyOffset, u32 valOffset, u16 valLen
  Strings are null-terminated latin-1 at absolute file offsets.

Note the language folder is data\\local\\LNG (not LANG) in these MPQs.
"""
import struct

# Later files override earlier ones, matching the game's lookup order.
TABLES = [
    'data\\local\\LNG\\ENG\\string.tbl',
    'data\\local\\LNG\\ENG\\expansionstring.tbl',
    'data\\local\\LNG\\ENG\\patchstring.tbl',
]


def _cstr(data, off):
    return data[off:data.index(b'\x00', off)].decode('latin-1')


def parse(data):
    """One .tbl file -> dict key -> value."""
    nelem, = struct.unpack_from('<H', data, 2)
    hashsize, = struct.unpack_from('<I', data, 4)
    base = 21 + 2 * nelem
    out = {}
    for i in range(hashsize):
        off = base + i * 17
        if not data[off]:                       # unused hash slot
            continue
        keyoff, valoff = struct.unpack_from('<II', data, off + 7)
        out[_cstr(data, keyoff)] = _cstr(data, valoff)
    return out


def load(mpq, tables=None):
    """Merged English string table from an MPQSet (absent files are skipped)."""
    merged = {}
    for path in (tables or TABLES):
        try:
            merged.update(parse(mpq.read(path)))
        except FileNotFoundError:
            pass
    return merged
