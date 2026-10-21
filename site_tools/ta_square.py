"""Square-arena frames (four 64x64 modules tiled 2x2 -> 128x128 taxels, 256 x 256 mm), following
pipeline/peak_seed_contact_detector.m 'square' layout: hardware ids 1,2,3,4 at top-left, top-right,
bottom-left, bottom-right, rotated rot90 / none / rot180 / rot270 (MATLAB rot90 = numpy rot90, counter-clockwise)."""
import numpy as np
from ta_frames import Runway

POS = {1: (0, 0), 2: (0, 1), 3: (1, 0), 4: (1, 1)}
ROT = {1: 1, 2: 0, 3: 2, 4: 3}


class Square(Runway):
    def __init__(self, cache_path):
        super().__init__(cache_path)
        self.by_hid = {bd["hid"]: bd for bd in self.boards}

    def frame(self, t, with_mask=False):
        img = np.zeros((128, 128), np.float32); mask = np.zeros((128, 128), bool)
        for hid, bd in self.by_hid.items():
            p = int(np.searchsorted(bd["ts"], t, side="right")) - 1
            mod = np.zeros(4096, np.float32); rd = np.zeros(4096, bool)
            if p >= 0:
                a, b = bd["off"][p], bd["off"][p + 1]
                v = bd["val"][a:b].astype(np.float32); v[v > 4095] = 0
                mod[bd["rc"][a:b]] = v; rd[bd["rc"][a:b]] = True
            m = np.rot90(mod.reshape(64, 64), ROT[hid]); r_ = np.rot90(rd.reshape(64, 64), ROT[hid])
            gr, gc = POS[hid]
            img[64 * gr:64 * gr + 64, 64 * gc:64 * gc + 64] = m
            mask[64 * gr:64 * gr + 64, 64 * gc:64 * gc + 64] = r_
        return (img, mask) if with_mask else img
