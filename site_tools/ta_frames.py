"""Rebuild TactileArena runway pressure frames from a ta_extract cache, the way the paper's pipeline does:
each board's image is its most recent packet (values at the taxels it measured, zeros elsewhere), and boards
are placed left to right by hardware id 4|3|2|1. Also returns which taxels were measured in that packet."""
import numpy as np

LAYOUT_IDS = [4, 3, 2, 1]


class Runway:
    def __init__(self, cache_path):
        z = np.load(cache_path)
        self.z = z
        self.boards = []  # left to right
        by_id = {}
        for b in [1, 2, 3, 4]:
            hid = int(np.unique(z[f"b{b}_ids"])[0])
            by_id[hid] = dict(ts=z[f"b{b}_ts"], off=z[f"b{b}_off"], idx=z[f"b{b}_idx"].astype(np.int32),
                              val=z[f"b{b}_val"], name=f"Board{b}", hid=hid)
        self.boards = [by_id[h] for h in LAYOUT_IDS]
        for bd in self.boards:
            i = bd["idx"]
            left = i < 2048
            r = np.where(left, i // 32, (i - 2048) // 32)
            c = np.where(left, i % 32, (i - 2048) % 32 + 32)
            bd["rc"] = (r * 64 + c).astype(np.int32)  # flat index within the 64x64 module
        self.cam_ts = {c: z[f"cam{c}_ts"] for c in (0, 1)}
        self.t_end = min(bd["ts"][-1] for bd in self.boards)
        self.M = int(z["M"])

    def packet(self, k, t):
        """Index of board k's most recent packet at time t (or -1)."""
        return int(np.searchsorted(self.boards[k]["ts"], t, side="right")) - 1

    def frame(self, t, with_mask=False):
        img = np.zeros((64, 256), np.float32)
        mask = np.zeros((64, 256), bool) if with_mask else None
        for k, bd in enumerate(self.boards):
            p = self.packet(k, t)
            if p < 0:
                continue
            a, b = bd["off"][p], bd["off"][p + 1]
            flat = bd["rc"][a:b]
            mod = np.zeros(64 * 64, np.float32)
            mod[flat] = bd["val"][a:b]
            img[:, 64 * k:64 * (k + 1)] = mod.reshape(64, 64)
            if with_mask:
                m = np.zeros(64 * 64, bool); m[flat] = True
                mask[:, 64 * k:64 * (k + 1)] = m.reshape(64, 64)
        return (img, mask) if with_mask else img

    def frames(self, times, with_mask=False):
        out = np.zeros((len(times), 64, 256), np.uint16)
        masks = np.zeros((len(times), 64, 256), bool) if with_mask else None
        for i, t in enumerate(times):
            if with_mask:
                f, m = self.frame(t, True); masks[i] = m
            else:
                f = self.frame(t)
            out[i] = f
        return (out, masks) if with_mask else out
