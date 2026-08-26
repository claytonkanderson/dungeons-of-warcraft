"""Minimal WDC5 (db2) reader — enough for dense creature-display tables.

Yields rows as {id: [field0, field1, ...]} where array fields are lists.
Column meaning is left to the caller (schemas vary per build; we identify
columns empirically instead of shipping .dbd definitions).
"""
import struct


class DB2Error(RuntimeError):
    pass


class WDC5:
    def __init__(self, data: bytes):
        if data[:4] != b"WDC5":
            raise DB2Error(f"unsupported magic {data[:4]!r}")
        # u32 schema version + 128-byte build string, then WDC3-style header
        o = 4 + 4 + 128
        (self.record_count, self.field_count, self.record_size,
         self.string_table_size, self.table_hash, self.layout_hash,
         self.min_id, self.max_id, self.locale) = struct.unpack_from("<9I", data, o)
        o += 36
        (self.flags, self.id_index) = struct.unpack_from("<HH", data, o)
        o += 4
        (self.total_field_count, self.bitpacked_ofs, self.lookup_col_count,
         self.fsi_size, self.common_size, self.pallet_size,
         self.section_count) = struct.unpack_from("<7I", data, o)
        o += 28

        if self.flags & 1:
            raise DB2Error("sparse (offset-map) db2 not supported")

        sections = []
        for _ in range(self.section_count):
            (tact, file_ofs, rec_count, str_size, _rec_end, id_list_size,
             rel_size, ofsmap_count, copy_count) = \
                struct.unpack_from("<Q8I", data, o)
            sections.append(dict(tact=tact, ofs=file_ofs, n=rec_count,
                                 str_size=str_size, id_list=id_list_size,
                                 rel=rel_size, ofsmap=ofsmap_count,
                                 copy=copy_count))
            o += 40

        o += 4 * self.total_field_count  # legacy field structures

        self.fsi = []
        for _ in range(self.fsi_size // 24):
            (fo, fs, extra, stype, v1, v2, v3) = \
                struct.unpack_from("<HHIIIII", data, o)
            self.fsi.append(dict(offset=fo, size=fs, extra=extra,
                                 type=stype, v1=v1, v2=v2, v3=v3))
            o += 24

        pallet_base = o
        pallets = []
        for f in self.fsi:
            if f["type"] in (3, 4):
                cnt = f["extra"] // 4
                pallets.append(struct.unpack_from(f"<{cnt}I", data, o))
                o += f["extra"]
            else:
                pallets.append(None)
        commons = []
        for f in self.fsi:
            if f["type"] == 2:
                cnt = f["extra"] // 8
                m = {}
                for i in range(cnt):
                    rid, val = struct.unpack_from("<II", data, o + 8 * i)
                    m[rid] = val
                commons.append(m)
                o += f["extra"]
            else:
                commons.append(None)
        self.pallets, self.commons = pallets, commons

        self.rows = {}
        self.relation = {}
        for sec in sections:
            if sec["tact"] and all(
                    b == 0 for b in data[sec["ofs"]:sec["ofs"] + 64]):
                continue  # encrypted section not present locally
            base = sec["ofs"]
            recs = base + self.record_size * sec["n"]
            strings = recs  # string table follows records
            id_base = strings + sec["str_size"]
            ids = struct.unpack_from(f"<{sec['id_list']//4}I", data, id_base)
            copy_base = id_base + sec["id_list"]
            rel_base = copy_base + sec["copy"] * 8
            rel_map = {}
            if sec["rel"]:
                cnt = struct.unpack_from("<I", data, rel_base)[0]
                for i in range(cnt):
                    fid, ridx = struct.unpack_from("<II", data,
                                                   rel_base + 12 + 8 * i)
                    rel_map[ridx] = fid
            for ri in range(sec["n"]):
                rec = data[base + ri * self.record_size:
                           base + (ri + 1) * self.record_size]
                rid = ids[ri] if ids else None
                row = self._decode(rec, rid)
                if rid is None:
                    rid = row[self.id_index]
                self.rows[rid] = row
                if ri in rel_map:
                    self.relation[rid] = rel_map[ri]
            for ci in range(sec["copy"]):
                dst, src = struct.unpack_from("<II", data, copy_base + 8 * ci)
                if src in self.rows:
                    self.rows[dst] = self.rows[src]
                    if src in self.relation:
                        self.relation[dst] = self.relation[src]

    def _decode(self, rec: bytes, rid):
        big = int.from_bytes(rec, "little")
        out = []
        for fi, f in enumerate(self.fsi):
            t = f["type"]
            if t == 0:
                bits = f["size"]
                if bits >= 64 and bits % 32 == 0 and bits != 64:
                    n = bits // 32
                    vals = [(big >> (f["offset"] + 32 * i)) & 0xFFFFFFFF
                            for i in range(n)]
                    out.append(vals)
                else:
                    out.append((big >> f["offset"]) & ((1 << bits) - 1))
            elif t in (1, 5):
                v = (big >> f["offset"]) & ((1 << f["size"]) - 1)
                if t == 5 and v >> (f["size"] - 1):
                    v -= 1 << f["size"]
                out.append(v)
            elif t == 2:
                out.append(self.commons[fi].get(rid, f["v1"]))
            elif t == 3:
                idx = (big >> f["offset"]) & ((1 << f["size"]) - 1)
                out.append(self.pallets[fi][idx])
            elif t == 4:
                idx = (big >> f["offset"]) & ((1 << f["size"]) - 1)
                n = f["v3"]
                p = self.pallets[fi]
                out.append(list(p[idx * n:(idx + 1) * n]))
            else:
                raise DB2Error(f"storage type {t}")
        return out


if __name__ == "__main__":
    import sys
    from casc import Storage
    s = Storage(verbose=False)
    name, row_id = sys.argv[1], int(sys.argv[2])
    db = WDC5(s.read_path(f"dbfilesclient/{name}.db2"))
    print(f"{name}: {len(db.rows)} rows, {len(db.fsi)} fields, "
          f"flags={db.flags:#x} id_index={db.id_index} "
          f"lookup_cols={db.lookup_col_count}")
    row = db.rows.get(row_id)
    print(f"row {row_id}:")
    if row:
        for i, v in enumerate(row):
            print(f"  [{i}] {v}")
        if row_id in db.relation:
            print("  relation:", db.relation[row_id])
    else:
        print("  (missing)")
