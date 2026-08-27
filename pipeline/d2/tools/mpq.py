"""Minimal pure-Python MPQ v1 reader sufficient for Diablo II archives.

Supports: hash/block table decryption, encrypted files (with FIX_KEY),
single-unit and sector-based files, zlib and PKWARE DCL (implode) compression.
"""
import struct
import zlib
import os

# ---------------------------------------------------------------------------
# Crypt table / hashing
# ---------------------------------------------------------------------------
_CRYPT = [0] * 0x500
_seed = 0x00100001
for i in range(0x100):
    idx = i
    for _ in range(5):
        _seed = (_seed * 125 + 3) % 0x2AAAAB
        t1 = (_seed & 0xFFFF) << 0x10
        _seed = (_seed * 125 + 3) % 0x2AAAAB
        t2 = _seed & 0xFFFF
        _CRYPT[idx] = t1 | t2
        idx += 0x100

HASH_TABLE_OFFSET, HASH_NAME_A, HASH_NAME_B, HASH_FILE_KEY = 0, 1, 2, 3


def hash_string(s, htype):
    seed1, seed2 = 0x7FED7FED, 0xEEEEEEEE
    for ch in s.upper().replace('/', '\\').encode('latin-1'):
        seed1 = (_CRYPT[(htype << 8) + ch] ^ ((seed1 + seed2) & 0xFFFFFFFF)) & 0xFFFFFFFF
        seed2 = (ch + seed1 + seed2 + (seed2 << 5) + 3) & 0xFFFFFFFF
    return seed1


def decrypt(data, key):
    n = len(data) // 4
    words = list(struct.unpack('<%dI' % n, data[:n * 4]))
    seed = 0xEEEEEEEE
    for i in range(n):
        seed = (seed + _CRYPT[0x400 + (key & 0xFF)]) & 0xFFFFFFFF
        ch = words[i] ^ ((key + seed) & 0xFFFFFFFF)
        key = (((~key << 0x15) + 0x11111111) | (key >> 0x0B)) & 0xFFFFFFFF
        seed = (ch + seed + (seed << 5) + 3) & 0xFFFFFFFF
        words[i] = ch
    return struct.pack('<%dI' % n, *words) + data[n * 4:]


# ---------------------------------------------------------------------------
# PKWARE DCL explode
# ---------------------------------------------------------------------------
_LEN_BITS = [3, 2, 3, 3, 4, 4, 4, 5, 5, 5, 5, 6, 6, 6, 7, 7]
_LEN_CODE = [5, 3, 1, 6, 10, 2, 12, 20, 4, 24, 8, 48, 16, 32, 64, 0]
_EX_LEN_BITS = [0, 0, 0, 0, 0, 0, 0, 0, 1, 2, 3, 4, 5, 6, 7, 8]
_LEN_BASE = [0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 14, 22, 38, 70, 134, 262]
_DIST_BITS = [2, 4, 4, 5, 5, 5, 5, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7,
              7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8]
_DIST_CODE = [0x03, 0x0D, 0x05, 0x19, 0x09, 0x11, 0x01, 0x3E, 0x1E, 0x2E, 0x0E, 0x36, 0x16, 0x26, 0x06, 0x3A,
              0x1A, 0x2A, 0x0A, 0x32, 0x12, 0x22, 0x42, 0x02, 0x7C, 0x3C, 0x5C, 0x1C, 0x6C, 0x2C, 0x4C, 0x0C,
              0x74, 0x34, 0x54, 0x14, 0x64, 0x24, 0x44, 0x04, 0x78, 0x38, 0x58, 0x18, 0x68, 0x28, 0x48, 0x08,
              0xF0, 0x70, 0xB0, 0x30, 0xD0, 0x50, 0x90, 0x10, 0xE0, 0x60, 0xA0, 0x20, 0xC0, 0x40, 0x80, 0x00]
_CH_BITS_ASC = [
    0x0B, 0x0C, 0x0C, 0x0B, 0x0C, 0x0C, 0x0C, 0x0C, 0x0C, 0x0C, 0x0C, 0x0C, 0x0C, 0x0C, 0x0C, 0x0C,
    0x0C, 0x0C, 0x0C, 0x0C, 0x0C, 0x0C, 0x0D, 0x0C, 0x0C, 0x0C, 0x0C, 0x0C, 0x0C, 0x0C, 0x0C, 0x0C,
    0x04, 0x0A, 0x08, 0x0C, 0x0A, 0x0C, 0x0A, 0x08, 0x07, 0x07, 0x08, 0x09, 0x07, 0x06, 0x07, 0x08,
    0x07, 0x06, 0x07, 0x07, 0x07, 0x07, 0x08, 0x07, 0x07, 0x08, 0x08, 0x0C, 0x0B, 0x07, 0x09, 0x0B,
    0x0C, 0x06, 0x07, 0x06, 0x06, 0x05, 0x07, 0x08, 0x08, 0x06, 0x0B, 0x09, 0x06, 0x07, 0x06, 0x06,
    0x07, 0x0B, 0x06, 0x06, 0x06, 0x07, 0x09, 0x08, 0x09, 0x09, 0x0B, 0x08, 0x0B, 0x09, 0x0C, 0x08,
    0x0C, 0x05, 0x06, 0x06, 0x06, 0x05, 0x06, 0x06, 0x06, 0x05, 0x0B, 0x07, 0x05, 0x06, 0x05, 0x05,
    0x06, 0x0A, 0x05, 0x05, 0x05, 0x05, 0x08, 0x07, 0x08, 0x08, 0x0A, 0x0B, 0x0B, 0x0C, 0x0C, 0x0C,
    0x0D, 0x0D, 0x0D, 0x0C, 0x0D, 0x0D, 0x0D, 0x0C, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0C, 0x0D, 0x0D,
    0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D,
    0x0C, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D,
    0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D,
    0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D,
    0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D,
    0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D,
    0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D, 0x0D]
_CH_CODE_ASC = [
    0x0490, 0x0FE0, 0x07E0, 0x0BE0, 0x03E0, 0x0DE0, 0x05E0, 0x09E0, 0x01E0, 0x00B8, 0x0062, 0x0EE0, 0x06E0, 0x0022, 0x0AE0, 0x02E0,
    0x0CE0, 0x04E0, 0x08E0, 0x00E0, 0x0F60, 0x0760, 0x1F60, 0x0B60, 0x0360, 0x0D60, 0x0560, 0x1240, 0x0960, 0x0160, 0x0E60, 0x0660,
    0x0000, 0x0038, 0x0018, 0x0A60, 0x0278, 0x0260, 0x0058, 0x0030, 0x0004, 0x0034, 0x0014, 0x0170, 0x0001, 0x0008, 0x0011, 0x0028,
    0x001C, 0x0012, 0x0021, 0x0069, 0x0032, 0x006A, 0x0040, 0x0079, 0x0009, 0x0070, 0x0050, 0x0360, 0x0018, 0x0002, 0x0180, 0x01C0,
    0x01E0, 0x0035, 0x0031, 0x0006, 0x0025, 0x0000, 0x0026, 0x0064, 0x0024, 0x000E, 0x04F0, 0x0178, 0x0030, 0x0023, 0x000B, 0x0007,
    0x0013, 0x0560, 0x0015, 0x0010, 0x0003, 0x0067, 0x0140, 0x00A0, 0x0044, 0x0144, 0x0068, 0x000C, 0x03E0, 0x0008, 0x0224, 0x0044,
    0x0BE0, 0x0007, 0x0023, 0x0012, 0x0005, 0x0002, 0x0021, 0x0003, 0x0021, 0x000D, 0x00C8, 0x0033, 0x002C, 0x0011, 0x0016, 0x0003,
    0x0001, 0x0108, 0x001A, 0x0002, 0x000A, 0x0013, 0x0078, 0x0041, 0x0088, 0x0028, 0x0038, 0x0074, 0x0062, 0x07E0, 0x0FA0, 0x0AA0,
    0x0320, 0x1320, 0x0B20, 0x0D20, 0x0520, 0x1520, 0x0920, 0x0120, 0x1120, 0x0E20, 0x0620, 0x1620, 0x0A20, 0x0220, 0x1220, 0x0C20,
    0x0420, 0x1420, 0x0820, 0x0020, 0x1020, 0x0FC0, 0x07C0, 0x17C0, 0x0BC0, 0x03C0, 0x13C0, 0x0DC0, 0x05C0, 0x15C0, 0x09C0, 0x01C0,
    0x0CA0, 0x11C0, 0x0EC0, 0x06C0, 0x16C0, 0x0AC0, 0x02C0, 0x12C0, 0x0CC0, 0x04C0, 0x14C0, 0x08C0, 0x00C0, 0x10C0, 0x0FA0, 0x07A0,
    0x17A0, 0x0BA0, 0x03A0, 0x13A0, 0x0DA0, 0x05A0, 0x15A0, 0x09A0, 0x01A0, 0x11A0, 0x0EA0, 0x06A0, 0x16A0, 0x0AA0, 0x02A0, 0x12A0,
    0x0CA0, 0x04A0, 0x14A0, 0x08A0, 0x00A0, 0x10A0, 0x0F60, 0x0760, 0x1760, 0x0B60, 0x0360, 0x1360, 0x0D60, 0x0560, 0x1560, 0x0960,
    0x0160, 0x1160, 0x0E60, 0x0660, 0x1660, 0x0A60, 0x0260, 0x1260, 0x0C60, 0x0460, 0x1460, 0x0860, 0x0060, 0x1060, 0x0FE0, 0x07E0,
    0x17E0, 0x0BE0, 0x03E0, 0x13E0, 0x0DE0, 0x05E0, 0x15E0, 0x09E0, 0x01E0, 0x11E0, 0x0EE0, 0x06E0, 0x16E0, 0x0AE0, 0x02E0, 0x12E0,
    0x0CE0, 0x04E0, 0x14E0, 0x08E0, 0x00E0, 0x10E0, 0x0F80, 0x0780, 0x1780, 0x0B80, 0x0380, 0x1380, 0x0D80, 0x0580, 0x1580, 0x0980]


def _gen_decode_tabs(bits, codes):
    tab = [0] * 256
    for i in range(len(bits)):
        b = bits[i]
        c = codes[i]
        while c < 256:
            tab[c] = i
            c += 1 << b
    return tab


_LEN_TAB = _gen_decode_tabs(_LEN_BITS, _LEN_CODE)
_DIST_TAB = _gen_decode_tabs(_DIST_BITS, _DIST_CODE)


def _gen_asc_tabs():
    tabs = {}
    # offs2C32 tables: index by (bits) for ascii mode
    for n, bits, codes in [('pos', _CH_BITS_ASC, _CH_CODE_ASC)]:
        pass
    return tabs


def explode(data):
    """PKWARE DCL decompression (the 'implode' format)."""
    if len(data) < 2:
        raise ValueError('too short')
    ctype = data[0]
    dsize_bits = data[1]
    if ctype not in (0, 1) or dsize_bits < 4 or dsize_bits > 6:
        raise ValueError('bad explode header')
    out = bytearray()
    pos = 2
    bitbuf = data[pos] if pos < len(data) else 0
    pos += 1
    extra = 0  # bits available beyond the 8 in bitbuf... we use an int stream instead

    # Simpler: treat the rest as an LSB-first bit stream
    class BS:
        __slots__ = ('d', 'p', 'buf', 'n')

        def __init__(self, d, p):
            self.d, self.p, self.buf, self.n = d, p, 0, 0

        def peek(self, k):
            while self.n < k:
                b = self.d[self.p] if self.p < len(self.d) else 0
                if self.p >= len(self.d) + 4:
                    raise EOFError
                self.p += 1
                self.buf |= b << self.n
                self.n += 8
            return self.buf & ((1 << k) - 1)

        def skip(self, k):
            self.buf >>= k
            self.n -= k

        def get(self, k):
            v = self.peek(k)
            self.skip(k)
            return v

    bs = BS(data, 2)
    # ascii decode: build lookup for binary-search-free decode of char codes
    if ctype == 1:
        asc_map = {}
        for ch in range(256):
            asc_map.setdefault(_CH_BITS_ASC[ch], {})[_CH_CODE_ASC[ch]] = ch
        asc_bits_sorted = sorted(asc_map.keys())
    while True:
        try:
            flag = bs.get(1)
        except EOFError:
            break
        if flag:
            # repeat
            lcode = _LEN_TAB[bs.peek(8)]
            bs.skip(_LEN_BITS[lcode])
            if _EX_LEN_BITS[lcode]:
                length = _LEN_BASE[lcode] + bs.get(_EX_LEN_BITS[lcode])
            else:
                length = _LEN_BASE[lcode]
            length += 2
            if length == 519:
                break
            dcode = _DIST_TAB[bs.peek(8)]
            bs.skip(_DIST_BITS[dcode])
            if length == 2:
                dist = (dcode << 2) | bs.get(2)
            else:
                dist = (dcode << dsize_bits) | bs.get(dsize_bits)
            dist += 1
            if dist > len(out):
                raise ValueError('bad distance')
            start = len(out) - dist
            for i in range(length):
                out.append(out[start + i])
        else:
            if ctype == 0:
                out.append(bs.get(8))
            else:
                found = False
                for b in asc_bits_sorted:
                    code = bs.peek(b)
                    m = asc_map[b]
                    if code in m:
                        bs.skip(b)
                        out.append(m[code])
                        found = True
                        break
                if not found:
                    raise ValueError('bad ascii code')
    return bytes(out)


# ---------------------------------------------------------------------------
# Adaptive huffman (FGK variant, port of StormLib huff.cpp) — used for WAVs
# ---------------------------------------------------------------------------
from huff_tables import WEIGHT_TABLES


class _HuffItem:
    __slots__ = ('nxt', 'prv', 'parent', 'child_lo', 'weight', 'value')

    def __init__(self, value=0, weight=0):
        self.nxt = self.prv = self.parent = self.child_lo = None
        self.value = value
        self.weight = weight


class _HuffBits:
    """LSB-first bit reader matching StormLib TInputStream semantics."""
    __slots__ = ('d', 'p', 'buf', 'n')

    def __init__(self, data):
        self.d, self.p, self.buf, self.n = data, 0, 0, 0

    def get1(self):
        if self.n == 0:
            if self.p >= len(self.d):
                return None
            self.buf = self.d[self.p]
            self.p += 1
            self.n = 8
        v = self.buf & 1
        self.buf >>= 1
        self.n -= 1
        return v

    def get8(self):
        if self.n < 8:
            if self.p >= len(self.d):
                return None
            self.buf |= self.d[self.p] << self.n
            self.p += 1
            self.n += 8
        v = self.buf & 0xFF
        self.buf >>= 8
        self.n -= 8
        return v


class _HuffTree:
    """List-threaded huffman tree: items form a circular doubly-linked list
    (head sentinel) sorted by descending weight; head.nxt is the root.
    A parent's low child is child_lo, its high child is child_lo.prv."""

    def __init__(self):
        head = _HuffItem()
        head.nxt = head.prv = head
        self.head = head
        self.by_byte = [None] * 258
        self.count = 0

    def _link_after(self, item1, item2):
        # insert item2 right after item1
        item2.nxt = item1.nxt
        item2.prv = item1.nxt.prv
        item1.nxt.prv = item2
        item1.nxt = item2

    def _remove(self, item):
        if item.nxt is not None:
            item.prv.nxt = item.nxt
            item.nxt.prv = item.prv
            item.nxt = item.prv = None

    def _find_higher_or_equal(self, item, weight):
        while item is not None and item is not self.head:
            if item.weight >= weight:
                return item
            item = item.prv
        return self.head

    def _new_item(self, value, weight, at_front):
        if self.count >= 1024:
            raise ValueError('huffman tree overflow')
        self.count += 1
        item = _HuffItem(value, weight)
        if at_front:
            self._link_after(self.head, item)
        else:
            self._link_after(self.head.prv, item)
        return item

    def _fixup_pos(self, item, max_weight):
        if item.weight < max_weight:
            higher = self._find_higher_or_equal(self.head.prv, item.weight)
            self._remove(item)
            self._link_after(higher, item)
            return max_weight
        return item.weight

    def build(self, dtype):
        weights = WEIGHT_TABLES[dtype & 0x0F]
        max_w = 0
        for i in range(256):
            if weights[i]:
                self.by_byte[i] = item = self._new_item(i, weights[i], True)
                max_w = self._fixup_pos(item, max_w)
        self.by_byte[0x100] = self._new_item(0x100, 1, False)
        self.by_byte[0x101] = self._new_item(0x101, 1, False)
        # pair up from the tail (lowest weights) to build the tree
        child_lo = self.head.prv
        while child_lo is not self.head:
            child_hi = child_lo.prv
            if child_hi is self.head:
                break
            parent = self._new_item(0, child_hi.weight + child_lo.weight, True)
            child_lo.parent = parent
            child_hi.parent = parent
            parent.child_lo = child_lo
            max_w = self._fixup_pos(parent, max_w)
            child_lo = child_hi.prv

    def inc_weights(self, item):
        while item is not None:
            item.weight += 1
            higher = self._find_higher_or_equal(item.prv, item.weight)
            child_hi = higher.nxt
            if child_hi is not item:
                # swap list positions and parent/child links to keep the
                # sibling property (child_hi.weight >= child_lo.weight)
                self._remove(child_hi)
                self._link_after(item, child_hi)
                self._remove(item)
                self._link_after(higher, item)
                child_lo = child_hi.parent.child_lo
                parent = item.parent
                if parent.child_lo is item:
                    parent.child_lo = child_hi
                if child_lo is child_hi:
                    child_hi.parent.child_lo = item
                parent = item.parent
                item.parent = child_hi.parent
                child_hi.parent = parent
            item = item.parent

    def insert_new_branch(self, new_value):
        # the lowest-weight leaf becomes a parent of a copy of itself (hi)
        # and the never-seen byte (lo, weight 0)
        last = self.head.prv
        child_hi = self._new_item(last.value, last.weight, False)
        child_hi.parent = last
        self.by_byte[last.value] = child_hi
        child_lo = self._new_item(new_value, 0, False)
        child_lo.parent = last
        last.child_lo = child_lo
        self.by_byte[new_value] = child_lo
        self.inc_weights(child_lo)

    def decode(self, bs):
        item = self.head.nxt
        if item is self.head:
            return None
        while item.child_lo is not None:
            bit = bs.get1()
            if bit is None:
                return None
            item = item.child_lo.prv if bit else item.child_lo
        return item.value


def huff_decompress(data):
    bs = _HuffBits(data)
    dtype = bs.get8()
    if dtype is None:
        raise ValueError('empty huffman stream')
    sparse = dtype == 0
    tree = _HuffTree()
    tree.build(dtype)
    out = bytearray()
    while True:
        v = tree.decode(bs)
        if v is None:
            raise ValueError('huffman stream error')
        if v == 0x100:  # end of stream
            break
        if v == 0x101:  # escape: literal byte follows
            v = bs.get8()
            if v is None:
                raise ValueError('huffman stream truncated')
            tree.insert_new_branch(v)
            if not sparse:
                tree.inc_weights(tree.by_byte[v])
        out.append(v)
        if sparse:
            tree.inc_weights(tree.by_byte[v])
    return bytes(out)


# ---------------------------------------------------------------------------
# Blizzard ADPCM (port of StormLib adpcm.cpp DecompressADPCM) — WAV sectors
# ---------------------------------------------------------------------------
_ADPCM_NEXT_STEP = [-1, 0, -1, 4, -1, 2, -1, 6, -1, 1, -1, 5, -1, 3, -1, 7,
                    -1, 1, -1, 5, -1, 3, -1, 7, -1, 2, -1, 4, -1, 6, -1, 8]
_ADPCM_STEP_SIZE = [
    7, 8, 9, 10, 11, 12, 13, 14, 16, 17, 19, 21, 23, 25, 28, 31,
    34, 37, 41, 45, 50, 55, 60, 66, 73, 80, 88, 97, 107, 118, 130, 143,
    157, 173, 190, 209, 230, 253, 279, 307, 337, 371, 408, 449, 494, 544, 598, 658,
    724, 796, 876, 963, 1060, 1166, 1282, 1411, 1552, 1707, 1878, 2066,
    2272, 2499, 2749, 3024, 3327, 3660, 4026, 4428, 4871, 5358, 5894, 6484,
    7132, 7845, 8630, 9493, 10442, 11487, 12635, 13899,
    15289, 16818, 18500, 20350, 22385, 24623, 27086, 29794, 32767]


def adpcm_decompress(data, channels):
    if len(data) < 2 + 2 * channels:
        return b''
    bit_shift = data[1]
    pos = 2
    pred = [0, 0]
    step_idx = [0x2C, 0x2C]
    out = bytearray()
    for i in range(channels):
        pred[i] = struct.unpack_from('<h', data, pos)[0]
        pos += 2
        out += struct.pack('<h', pred[i])
    ch = channels - 1
    end = len(data)
    while pos < end:
        enc = data[pos]
        pos += 1
        ch = (ch + 1) % channels
        if enc == 0x80:
            # silence run marker: repeat sample, soften the step
            if step_idx[ch] != 0:
                step_idx[ch] -= 1
            out += struct.pack('<h', pred[ch])
        elif enc == 0x81:
            # step-up marker (produces no sample; same channel goes next)
            step_idx[ch] = min(step_idx[ch] + 8, 0x58)
            ch = (ch + 1) % channels
        else:
            step = _ADPCM_STEP_SIZE[step_idx[ch]]
            diff = step >> bit_shift
            for b in range(6):
                if enc & (1 << b):
                    diff += step >> b
            if enc & 0x40:
                pred[ch] = max(pred[ch] - diff, -32768)
            else:
                pred[ch] = min(pred[ch] + diff, 32767)
            out += struct.pack('<h', pred[ch])
            step_idx[ch] = min(max(step_idx[ch] + _ADPCM_NEXT_STEP[enc & 0x1F], 0), 88)
    return bytes(out)


# ---------------------------------------------------------------------------
# Archive
# ---------------------------------------------------------------------------
FLAG_IMPLODE = 0x00000100
FLAG_COMPRESS = 0x00000200
FLAG_ENCRYPTED = 0x00010000
FLAG_FIX_KEY = 0x00020000
FLAG_SINGLE_UNIT = 0x01000000
FLAG_EXISTS = 0x80000000


def _decompress_multi(data):
    mask = data[0]
    data = data[1:]
    if mask & 0x01:  # huffman (always wraps adpcm audio)
        data = huff_decompress(data)
        mask &= ~0x01
    if mask & 0x08:
        data = explode(data)
        mask &= ~0x08
    if mask & 0x02:
        data = zlib.decompress(data)
        mask &= ~0x02
    if mask & 0x40:  # ADPCM mono
        data = adpcm_decompress(data, 1)
        mask &= ~0x40
    elif mask & 0x80:  # ADPCM stereo
        data = adpcm_decompress(data, 2)
        mask &= ~0x80
    if mask:
        raise NotImplementedError('compression mask %02x' % mask)
    return data


class MPQ:
    def __init__(self, path):
        self.path = path
        self.f = open(path, 'rb')
        self._find_header()
        self._read_tables()
        self.listfile = None

    def _find_header(self):
        self.f.seek(0)
        off = 0
        while True:
            self.f.seek(off)
            hdr = self.f.read(32)
            if len(hdr) < 32:
                raise ValueError('no MPQ header')
            if hdr[:4] == b'MPQ\x1a':
                break
            off += 0x200
        self.base = off
        (hsize, asize, fmt, bsize, hpos, bpos, hcount, bcount) = struct.unpack('<IIHHIIII', hdr[4:32])
        self.sector_size = 512 << bsize
        self.hpos, self.bpos, self.hcount, self.bcount = hpos, bpos, hcount, bcount

    def _read_tables(self):
        self.f.seek(self.base + self.hpos)
        raw = decrypt(self.f.read(self.hcount * 16), hash_string('(hash table)', HASH_FILE_KEY))
        self.hash = [struct.unpack_from('<IIHHI', raw, i * 16) for i in range(self.hcount)]
        self.f.seek(self.base + self.bpos)
        raw = decrypt(self.f.read(self.bcount * 16), hash_string('(block table)', HASH_FILE_KEY))
        self.block = [struct.unpack_from('<IIII', raw, i * 16) for i in range(self.bcount)]

    def find(self, name):
        idx = hash_string(name, HASH_TABLE_OFFSET) & (self.hcount - 1)
        a = hash_string(name, HASH_NAME_A)
        b = hash_string(name, HASH_NAME_B)
        start = idx
        while True:
            h = self.hash[idx]
            if h[4] == 0xFFFFFFFF:
                return None
            if h[0] == a and h[1] == b and h[4] != 0xFFFFFFFE:
                return h[4]
            idx = (idx + 1) & (self.hcount - 1)
            if idx == start:
                return None

    def has(self, name):
        return self.find(name) is not None

    def read(self, name):
        bi = self.find(name)
        if bi is None:
            raise FileNotFoundError(name)
        fpos, csize, fsize, flags = self.block[bi]
        if not flags & FLAG_EXISTS:
            raise FileNotFoundError(name)
        key = 0
        if flags & FLAG_ENCRYPTED:
            base = name.replace('/', '\\').split('\\')[-1]
            key = hash_string(base, HASH_FILE_KEY)
            if flags & FLAG_FIX_KEY:
                key = ((key + fpos) ^ fsize) & 0xFFFFFFFF
        self.f.seek(self.base + fpos)
        compressed = bool(flags & (FLAG_COMPRESS | FLAG_IMPLODE))
        if flags & FLAG_SINGLE_UNIT or not compressed:
            raw = self.f.read(csize)
            if flags & FLAG_ENCRYPTED:
                raw = decrypt(raw, key)
            if compressed and csize < fsize:
                raw = self._decomp(raw, flags)
            return raw[:fsize]
        nsect = (fsize + self.sector_size - 1) // self.sector_size
        offs_raw = self.f.read((nsect + 1) * 4)
        if flags & FLAG_ENCRYPTED:
            offs_raw = decrypt(offs_raw, (key - 1) & 0xFFFFFFFF)
        offs = struct.unpack('<%dI' % (nsect + 1), offs_raw)
        out = bytearray()
        for i in range(nsect):
            self.f.seek(self.base + fpos + offs[i])
            chunk = self.f.read(offs[i + 1] - offs[i])
            if flags & FLAG_ENCRYPTED:
                chunk = decrypt(chunk, (key + i) & 0xFFFFFFFF)
            want = min(self.sector_size, fsize - len(out))
            if len(chunk) < want:
                chunk = self._decomp(chunk, flags)
            out += chunk[:want]
        return bytes(out)

    def _decomp(self, chunk, flags):
        if flags & FLAG_COMPRESS:
            return _decompress_multi(chunk)
        return explode(chunk)

    def list(self):
        if self.listfile is None:
            try:
                txt = self.read('(listfile)').decode('latin-1')
                self.listfile = [l.strip() for l in txt.replace('\r', '\n').split('\n') if l.strip()]
            except FileNotFoundError:
                self.listfile = []
        return self.listfile


class MPQSet:
    """Search several archives in priority order (first wins)."""

    def __init__(self, paths):
        self.archives = [MPQ(p) for p in paths if os.path.exists(p)]

    def read(self, name):
        for a in self.archives:
            if a.has(name):
                return a.read(name)
        raise FileNotFoundError(name)

    def has(self, name):
        return any(a.has(name) for a in self.archives)

    def list(self):
        seen = set()
        out = []
        for a in self.archives:
            for n in a.list():
                k = n.lower()
                if k not in seen:
                    seen.add(k)
                    out.append(n)
        return out
