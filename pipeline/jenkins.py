"""Bob Jenkins lookup3 hashlittle2 — the name hash used by TACT root files.

WoW hashes the uppercased path with backslash separators; the 64-bit
lookup value stored in root is (c << 32) | b from hashlittle2 with both
seeds zero.
"""

MASK = 0xFFFFFFFF


def _rot(x, k):
    return ((x << k) | (x >> (32 - k))) & MASK


def _mix(a, b, c):
    a = (a - c) & MASK; a ^= _rot(c, 4);  c = (c + b) & MASK
    b = (b - a) & MASK; b ^= _rot(a, 6);  a = (a + c) & MASK
    c = (c - b) & MASK; c ^= _rot(b, 8);  b = (b + a) & MASK
    a = (a - c) & MASK; a ^= _rot(c, 16); c = (c + b) & MASK
    b = (b - a) & MASK; b ^= _rot(a, 19); a = (a + c) & MASK
    c = (c - b) & MASK; c ^= _rot(b, 4);  b = (b + a) & MASK
    return a, b, c


def _final(a, b, c):
    c ^= b; c = (c - _rot(b, 14)) & MASK
    a ^= c; a = (a - _rot(c, 11)) & MASK
    b ^= a; b = (b - _rot(a, 25)) & MASK
    c ^= b; c = (c - _rot(b, 16)) & MASK
    a ^= c; a = (a - _rot(c, 4)) & MASK
    b ^= a; b = (b - _rot(a, 14)) & MASK
    c ^= b; c = (c - _rot(b, 24)) & MASK
    return a, b, c


def hashlittle2(data: bytes, init_c: int = 0, init_b: int = 0):
    length = len(data)
    a = b = c = (0xDEADBEEF + length + init_c) & MASK
    c = (c + init_b) & MASK

    pos = 0
    while length > 12:
        a = (a + int.from_bytes(data[pos:pos + 4], "little")) & MASK
        b = (b + int.from_bytes(data[pos + 4:pos + 8], "little")) & MASK
        c = (c + int.from_bytes(data[pos + 8:pos + 12], "little")) & MASK
        a, b, c = _mix(a, b, c)
        pos += 12
        length -= 12

    if length == 0:
        return c, b
    tail = data[pos:pos + length] + b"\x00" * (12 - length)
    a = (a + int.from_bytes(tail[0:4], "little")) & MASK
    b = (b + int.from_bytes(tail[4:8], "little")) & MASK
    c = (c + int.from_bytes(tail[8:12], "little")) & MASK
    a, b, c = _final(a, b, c)
    return c, b


def path_hash(path: str) -> int:
    """64-bit TACT lookup hash for a virtual file path."""
    norm = path.upper().replace("/", "\\").encode("ascii")
    c, b = hashlittle2(norm)
    return (c << 32) | b
