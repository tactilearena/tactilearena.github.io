"""Reusable pieces for TactileArena media: a recording session (pressure + registered overhead video +
automatic paw labels) and a TaxelView that draws 2 mm taxels into any pixel rectangle."""
import os, json, csv, numpy as np
from scipy.ndimage import gaussian_filter
from PIL import Image, ImageDraw
from ta_frames import Runway
from ta_register import Rectifier, read_range
from media_common import WORK, REPO, pressure_rgba, font, PAW, THRESHOLD

SESSIONS = {
    "rat4_0224": dict(cache="cache/rat4_0224.npz", reg="cache/rat4_0224_selfcal.json",
                      video="data/rat4_0224/camera_1_20260224_163907.mp4",
                      stance=os.path.join(REPO, "demo", "expected", "stance_events.csv")),
}


def grade(f, black=0.27, chroma=0.2):
    """Neutral, dim camera with compressed highlights (floor -> near black, white fur -> mid grey)."""
    f = f.astype(np.float32)
    g = f.mean(axis=2, keepdims=True)
    f = (g + chroma * (f - g)) / 255.0
    f = np.clip((f - black) / (1 - black), 0, 1)
    return 12 + 165 * f / (f + 0.3) * 1.3


class Session:
    def __init__(self, name="rat4_0224"):
        c = SESSIONS[name]
        self.rw = Runway(os.path.join(WORK, c["cache"]))
        self.H = np.array(json.load(open(os.path.join(WORK, c["reg"])))["H_rot180px_to_taxel"])
        self.video = os.path.join(WORK, c["video"])
        self.cts = self.rw.cam_ts[1]
        self.stance = []
        if c.get("stance") and os.path.exists(c["stance"]):
            for r in csv.DictReader(open(c["stance"])):
                self.stance.append(dict(label=r["label"], t0=float(r["start_time"]), t1=float(r["end_time"]),
                                        x=float(r["centroid_x"]), y=float(r["centroid_y"])))

    def load_camera(self, t_a, t_b, view, grade_fn=grade):
        """Warp and grade the overhead frames covering [t_a, t_b] into the TaxelView's pixel grid."""
        rect = Rectifier(self.H, s=view.s, u0=view.u0, u1=view.u0 + view.W / view.s, v0=view.v0,
                         v1=view.v0 + view.H / view.s)
        k0 = max(int(np.searchsorted(self.cts, t_a)) - 2, 0)
        k1 = min(int(np.searchsorted(self.cts, t_b)) + 2, len(self.cts) - 1)
        raw = read_range(self.video, k0, k1 - k0 + 1)
        self._k0, self._k1 = k0, k1
        self._cam = np.stack([grade_fn(rect.warp(f))[:view.H, :view.W] for f in raw])

    def camera(self, t):
        kf = np.interp(t, self.cts[self._k0:self._k1 + 1], np.arange(self._k0, self._k1 + 1)) - self._k0
        a = int(np.floor(kf)); b = min(a + 1, len(self._cam) - 1); x = kf - a
        return self._cam[a] * (1 - x) + self._cam[b] * x

    def active_steps(self, t):
        return [s for s in self.stance if s["t0"] <= t <= s["t1"]]


class TaxelView:
    """Pixel grid of W x H where pixel (i, j) shows sensor taxel (row = v0 + i/s, col = u0 + j/s)."""

    def __init__(self, W, H, s, u0, v0):
        self.W, self.H, self.s, self.u0, self.v0 = W, H, s, u0, v0
        jj, ii = np.meshgrid(np.arange(W), np.arange(H))
        u = u0 + jj / s; v = v0 + ii / s
        col = np.floor(u).astype(int); row = np.floor(v).astype(int)
        self.valid = (col >= 0) & (col < 256) & (row >= 0) & (row < 64)
        g = max(1.0, 0.12 * s)
        self.cell = ((u - np.floor(u)) < (1 - g / s)) & ((v - np.floor(v)) < (1 - g / s))
        self.col = np.clip(col, 0, 255); self.row = np.clip(row, 0, 63)
        self.v = self.valid[..., None].astype(np.float32)

    @classmethod
    def fit(cls, W, u0=-4, u1=260, v0=-5, v1=69):
        s = W / (u1 - u0)
        H = int(round((v1 - v0) * s)); H -= H % 2
        return cls(W, H, s, u0, v0)

    def px(self, col, row):
        return ((col - self.u0 + 0.5) * self.s, (row - self.v0 + 0.5) * self.s)

    def lookup(self, A):
        return A[self.row, self.col]

    def overlay(self, base, P, halo=True, glow=(255, 120, 30), gain=1.4):
        if halo:
            act = np.clip((P.astype(np.float32) - THRESHOLD) / 2000, 0, 1)
            h = np.clip(gaussian_filter(act, 1.6) * 1.8, 0, 1)
            base = base + (self.lookup(h) * self.valid)[..., None] * np.array(glow, np.float32) * 0.55
        rgb, al = pressure_rgba(P)
        A = (np.clip(al * gain, 0, 1)[self.row, self.col] * self.valid)[..., None]
        cell = np.where(self.cell[..., None], rgb[self.row, self.col], 12.0)
        return base * (1 - A) + cell * A

    def floor(self, P, bg=(8, 9, 13), grid=(30, 32, 42), measured=None):
        """Tactile floor on its own: faint grid of every taxel, contacts in colour. If `measured` (bool
        64x256) is given, unmeasured taxels are black and measured-below-threshold taxels are dim grey."""
        out = np.empty((self.H, self.W, 3), np.float32); out[:] = bg
        if measured is None:
            gcol = np.where((self.cell & self.valid)[..., None], np.array(grid, np.float32), out)
        else:
            m = self.lookup(measured) & self.cell & self.valid
            gcol = np.where(m[..., None], np.array((70, 78, 96), np.float32), out)
            gcol = np.where((self.cell & self.valid & ~self.lookup(measured))[..., None],
                            np.array((14, 15, 20), np.float32), gcol)
        return self.overlay(gcol, P, halo=True)


def paw_tags(img, view, steps, P=None, size=22, ring=True):
    """Draw FL/FR/HL/HR tags at the automatic stance-event centroids (PIL image, in place)."""
    d = ImageDraw.Draw(img)
    f = font(size, "SemiBold")
    for s in steps:
        x, y = view.px(s["x"], s["y"])
        c = PAW[s["label"]]
        r = 5.5 * view.s
        if ring:
            d.ellipse([x - r, y - r, x + r, y + r], outline=c, width=max(2, int(view.s * 0.35)))
        tx, ty = x, y - r - 4
        bb = d.textbbox((tx, ty), s["label"], font=f, anchor="mb")
        d.rounded_rectangle([bb[0] - 6, bb[1] - 3, bb[2] + 6, bb[3] + 3], radius=5, fill=(10, 10, 14))
        d.text((tx, ty), s["label"], font=f, fill=c, anchor="mb")
    return img
