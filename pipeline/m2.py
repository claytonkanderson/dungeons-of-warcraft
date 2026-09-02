"""Parser for chunked (MD21) M2 models and their .skin companions.

Covers what a skinned, animated glTF export needs: vertices, bones with
animation tracks, sequences, textures, materials, batches. Track data for
sequences not embedded in the model is pulled from external .anim files
via a caller-supplied resolver.
"""
import struct

U32 = struct.Struct("<I")


def _u32(buf, o):
    return U32.unpack_from(buf, o)[0]


def _arr(buf, o):
    """M2Array {count, offset}"""
    return _u32(buf, o), _u32(buf, o + 4)


class Chunks(dict):
    @classmethod
    def parse(cls, data):
        self = cls()
        pos = 0
        while pos + 8 <= len(data):
            cid = data[pos:pos + 4]
            size = _u32(data, pos + 4)
            self[cid] = data[pos + 8:pos + 8 + size]
            pos += 8 + size
        return self


class Track:
    """M2Track: per-sequence keyframe arrays.

    `buf` is the buffer the track's offsets refer to (the MD21 payload,
    or a .skel chunk's data); `anim_chunk` names which chunk of a
    chunked .anim file holds this track's external data.
    """
    __slots__ = ("interp", "gseq", "times_hdr", "vals_hdr", "buf",
                 "anim_chunk")

    def __init__(self, buf, o, anim_chunk=b"AFM2"):
        self.interp = struct.unpack_from("<h", buf, o)[0]
        self.gseq = struct.unpack_from("<h", buf, o + 2)[0]
        self.times_hdr = _arr(buf, o + 4)   # M2Array<M2Array<u32>>
        self.vals_hdr = _arr(buf, o + 12)
        self.buf = buf
        self.anim_chunk = anim_chunk

    SIZE = 20

    def keys(self, model, seq_index, fmt, comps):
        """-> (times_ms list, values list-of-tuples) for one sequence."""
        if self.gseq >= 0:
            seq_index = 0  # global-sequence tracks keep data in entry 0
        n_t, o_t = self.times_hdr
        n_v, o_v = self.vals_hdr
        if seq_index >= n_t or seq_index >= n_v:
            return [], []
        tn, to = _arr(self.buf, o_t + 8 * seq_index)
        vn, vo = _arr(self.buf, o_v + 8 * seq_index)
        if tn == 0:
            return [], []
        if self.gseq >= 0 or model.seq_inline(seq_index):
            src = self.buf
        else:
            src = model.anim_bytes(seq_index, self.anim_chunk)
        if src is None:
            return [], []
        times = list(struct.unpack_from(f"<{tn}I", src, to))
        step = struct.calcsize(fmt) * comps
        raw = [struct.unpack_from(fmt * comps, src, vo + i * step)
               for i in range(vn)]
        if vn == 3 * tn:  # hermite/bezier: [value, in-tangent, out-tangent]
            raw = raw[0::3]
        return times, raw[:len(times)]


class Bone:
    __slots__ = ("key_bone", "flags", "parent", "trans", "rot", "scale", "pivot")
    SIZE = 88

    def __init__(self, buf, o, anim_chunk=b"AFM2"):
        self.key_bone = struct.unpack_from("<i", buf, o)[0]
        self.flags = _u32(buf, o + 4)
        self.parent = struct.unpack_from("<h", buf, o + 8)[0]
        self.trans = Track(buf, o + 16, anim_chunk)
        self.rot = Track(buf, o + 36, anim_chunk)
        self.scale = Track(buf, o + 56, anim_chunk)
        self.pivot = struct.unpack_from("<3f", buf, o + 76)


class Sequence:
    __slots__ = ("id", "variation", "duration", "flags", "alias_next")
    SIZE = 64

    def __init__(self, buf, o):
        self.id, self.variation = struct.unpack_from("<HH", buf, o)
        self.duration = _u32(buf, o + 4)
        self.flags = _u32(buf, o + 12)
        self.alias_next = struct.unpack_from("<H", buf, o + 62)[0]


class M2Model:
    def __init__(self, data: bytes, anim_resolver=None, file_loader=None):
        """anim_resolver(seq_id, variation, afid) -> bytes|None for external
        .anim files; file_loader(fdid) -> bytes for .skel support."""
        self._file_loader = file_loader
        self.chunks = Chunks.parse(data)
        md = self.md = self.chunks[b"MD21"]
        if md[:4] != b"MD20":
            raise ValueError("bad MD21 payload")
        self.version = _u32(md, 4)
        n, o = _arr(md, 8)
        self.name = md[o:o + n].rstrip(b"\0").decode("ascii", "replace")

        n, o = _arr(md, 0x14)
        self.global_seqs = list(struct.unpack_from(f"<{n}I", md, o)) if n else []
        n, o = _arr(md, 0x1C)
        self.sequences = [Sequence(md, o + i * Sequence.SIZE) for i in range(n)]
        n, o = _arr(md, 0x2C)
        self.bones = [Bone(md, o + i * Bone.SIZE) for i in range(n)]

        n, o = _arr(md, 0x3C)
        self.vertices = [struct.unpack_from("<3f4B4B3f2f2f", md, o + i * 48)
                         for i in range(n)]
        self.n_views = _u32(md, 0x44)

        # Collision ("bounding") geometry, carried only by models the client
        # treats as solid. It is the game's own answer to what blocks
        # movement: crates, cages and furniture have it, while foliage,
        # waterfalls and effects are meant to be walked straight through.
        self.collision_verts = _arr(md, 0xE0)[0]

        n, o = _arr(md, 0x50)  # {type u32, flags u32, name M2Array}
        self.textures = []
        for i in range(n):
            t = o + i * 16
            ln, ofs = _arr(md, t + 8)
            self.textures.append({
                "type": _u32(md, t),
                "flags": _u32(md, t + 4),
                "name": md[ofs:ofs + ln].rstrip(b"\0").decode("ascii", "replace"),
            })
        # attachment points: {id u32, bone u16, unk u16, pos vec3, track}
        n, o = _arr(md, 0xF0)
        self.attachments = []
        for i in range(n):
            a = o + i * 40
            self.attachments.append({
                "id": _u32(md, a),
                "bone": struct.unpack_from("<H", md, a + 4)[0],
                "pos": struct.unpack_from("<3f", md, a + 8),
            })

        n, o = _arr(md, 0x70)  # {flags u16, blend u16}
        self.materials = [struct.unpack_from("<HH", md, o + i * 4) for i in range(n)]
        n, o = _arr(md, 0x80)
        self.tex_lookup = list(struct.unpack_from(f"<{n}H", md, o)) if n else []

        self.sfid = list(struct.unpack(f"<{len(self.chunks[b'SFID'])//4}I",
                                       self.chunks[b"SFID"])) \
            if b"SFID" in self.chunks else []
        self.txid = list(struct.unpack(f"<{len(self.chunks[b'TXID'])//4}I",
                                       self.chunks[b"TXID"])) \
            if b"TXID" in self.chunks else []
        self.afid = {}
        if b"AFID" in self.chunks:
            c = self.chunks[b"AFID"]
            for i in range(0, len(c), 8):
                aid, sub, fdid = struct.unpack_from("<HHI", c, i)
                if fdid:
                    self.afid[(aid, sub)] = fdid

        # skeleton-file models: bones/sequences/attachments live in .skel
        if b"SKID" in self.chunks and file_loader:
            self._load_skeleton(
                struct.unpack("<I", self.chunks[b"SKID"][:4])[0])

        self._anim_resolver = anim_resolver
        self._anim_cache = {}
        self._anim_chunks_cache = {}

    def _load_skeleton(self, skel_fdid):
        chain = []
        fdid = skel_fdid
        for _ in range(4):  # child -> parent chain, bounded
            try:
                c = Chunks.parse(self._file_loader(fdid))
            except Exception:
                break
            chain.append(c)
            fdid = 0
            if b"SKPD" in c:
                pd = c[b"SKPD"]
                # parent fdid is the last plausible u32 in the chunk
                for o in range(len(pd) - 4, -1, -4):
                    v = struct.unpack_from("<I", pd, o)[0]
                    if 100000 < v < 10_000_000:
                        fdid = v
                        break
            if not fdid:
                break

        def first(cid):
            for c in chain:
                if cid in c:
                    return c[cid]
            return None

        skb = first(b"SKB1")
        if skb:
            n, o = _arr(skb, 0)
            self.bones = [Bone(skb, o + i * Bone.SIZE, b"AFSB")
                          for i in range(n)]
        sks = first(b"SKS1")
        if sks:
            n, o = _arr(sks, 0)
            self.global_seqs = list(struct.unpack_from(f"<{n}I", sks, o)) \
                if n else []
            n, o = _arr(sks, 8)
            self.sequences = [Sequence(sks, o + i * Sequence.SIZE)
                              for i in range(n)]
        ska = first(b"SKA1")
        if ska:
            n, o = _arr(ska, 0)
            self.attachments = []
            for i in range(n):
                a = o + i * 40
                self.attachments.append({
                    "id": _u32(ska, a),
                    "bone": struct.unpack_from("<H", ska, a + 4)[0],
                    "pos": struct.unpack_from("<3f", ska, a + 8),
                })
        afid = first(b"AFID")
        if afid:
            self.afid = {}
            for i in range(0, len(afid), 8):
                aid, sub, f = struct.unpack_from("<HHI", afid, i)
                if f:
                    self.afid[(aid, sub)] = f

    # ---------------------------------------------------------- sequences
    def seq_inline(self, seq_index):
        return bool(self.sequences[seq_index].flags & 0x20)

    def resolve_alias(self, seq_index):
        seen = set()
        while (self.sequences[seq_index].flags & 0x40) and seq_index not in seen:
            seen.add(seq_index)
            seq_index = self.sequences[seq_index].alias_next
        return seq_index

    def anim_bytes(self, seq_index, chunk=b"AFM2"):
        if seq_index not in self._anim_cache:
            seq = self.sequences[seq_index]
            data = None
            if self._anim_resolver:
                data = self._anim_resolver(seq.id, seq.variation, self.afid)
            self._anim_cache[seq_index] = data
            if data and data[:4] in (b"AFM2", b"AFSA", b"AFSB"):
                self._anim_chunks_cache[seq_index] = Chunks.parse(data)
            else:
                self._anim_chunks_cache[seq_index] = None
        data = self._anim_cache[seq_index]
        parsed = self._anim_chunks_cache.get(seq_index)
        if parsed is not None:
            return parsed.get(chunk)
        return data  # legacy raw .anim: offsets address the whole file


class Skin:
    def __init__(self, data: bytes):
        if data[:4] != b"SKIN":
            raise ValueError("bad skin magic")
        n, o = _arr(data, 4)
        self.vertices = list(struct.unpack_from(f"<{n}H", data, o))
        n, o = _arr(data, 12)
        self.indices = list(struct.unpack_from(f"<{n}H", data, o))
        n, o = _arr(data, 28)  # submeshes, 48 bytes each
        self.submeshes = []
        for i in range(n):
            s = o + i * 48
            (sid, level, vstart, vcount, istart, icount) = \
                struct.unpack_from("<6H", data, s)
            self.submeshes.append({
                "id": sid,
                "index_start": istart + (level << 16),
                "index_count": icount,
            })
        n, o = _arr(data, 36)  # batches, 24 bytes each
        self.batches = []
        for i in range(n):
            b = o + i * 24
            (_fl, _pp, shader, section, geoset, color, material, layer,
             ntex, texcombo) = struct.unpack_from("<BbHHHhHHHH", data, b)
            self.batches.append({
                "section": section,
                "material": material,
                "layer": layer,
                "tex_combo": texcombo,
            })
