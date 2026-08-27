"""Diablo II COF (component object file) parser — layer list and draw priority."""
import struct

COMPOSITES = ['HD', 'TR', 'LG', 'RA', 'LA', 'RH', 'LH', 'SH',
              'S1', 'S2', 'S3', 'S4', 'S5', 'S6', 'S7', 'S8']


class COF:
    def __init__(self, data):
        self.nlayers = data[0]
        self.nframes = data[1]
        self.ndirs = data[2]
        self.version = data[3]
        self.xmin, self.xmax, self.ymin, self.ymax = struct.unpack_from('<iiii', data, 8)
        pos = 28
        self.layers = []
        for _ in range(self.nlayers):
            comp, shadow, selectable, override_tr, new_tr = data[pos:pos + 5]
            wclass = data[pos + 5:pos + 9].split(b'\x00')[0].decode('latin-1')
            self.layers.append({'comp': COMPOSITES[comp], 'comp_idx': comp,
                                'shadow': shadow, 'transparent': override_tr,
                                'draw_effect': new_tr, 'wclass': wclass})
            pos += 9
        self.keyframes = list(data[pos:pos + self.nframes])
        pos += self.nframes
        n = self.ndirs * self.nframes * self.nlayers
        pri = list(data[pos:pos + n])
        # priority[dir][frame] = list of composite indices in draw order
        self.priority = []
        i = 0
        for _ in range(self.ndirs):
            byframe = []
            for _ in range(self.nframes):
                byframe.append(pri[i:i + self.nlayers])
                i += self.nlayers
            self.priority.append(byframe)
