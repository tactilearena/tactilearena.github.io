"""Supplementary Video 5: reconfiguration of the sensor modules into an open-field arena.
  1. title card
  2. square arena (four modules 2x2, 128x128 taxels), rat 4 on 2026-02-24 with the study's settings
     (M = 200, T = 700): tactile floor | overhead camera (rotated 180 deg, as in the pipeline) | side camera
  3. three rats exploring the square arena together (tactile map + overhead camera composite)
Camera MP4s are stamped 30 fps but were recorded at ~19-20 fps, so every frame is placed by its saved timestamp.
The excerpt (60.6-72.8 s) is a continuous stretch of the recording.
Usage: python make_supp_square.py out.mp4"""
import os, sys, subprocess, numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from PIL import Image
from scipy import ndimage as ndi
from scipy.ndimage import gaussian_filter
from ta_square import Square
from media_common import WORK, SOURCES, Writer, poster, pressure_rgba, THRESHOLD
from make_overview import (W, H, FPS, blank, to_img, to_arr, ease, text_block, caption, badge, EMBER, read_video,
                           arena_panels)

DATA = os.path.join(WORK, "data", "square_rat4_0224")
SQ = Square(os.path.join(WORK, "cache", "square_rat4_0224.npz"))
T_A, T_B = 60.6, 72.8   # longest stretch without a host-side stall that includes a rearing
SPEED = 0.75
PANEL = 590; Y0 = 190; XS = [40, 665, 1290]


def read_idx(path, k0, k1):
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-vf", f"select=between(n\\,{k0}\\,{k1})", "-fps_mode",
                          "passthrough", "-f", "rawvideo", "-pix_fmt", "rgb24", "-"], capture_output=True, check=True).stdout
    return np.frombuffer(raw, np.uint8).reshape(-1, 1080, 1920, 3)


class Cam:
    def __init__(self, c, crop, rot180):
        ts = SQ.cam_ts[c]
        self.k0 = max(int(np.searchsorted(ts, T_A)) - 2, 0); self.k1 = min(int(np.searchsorted(ts, T_B)) + 2, len(ts) - 1)
        self.ts = ts[self.k0:self.k1 + 1]
        fr = read_idx(os.path.join(DATA, f"camera_{c}_20260224_160255.mp4"), self.k0, self.k1)
        x0, y0, x1, y1 = crop
        out = []
        for f in fr:
            if rot180:
                f = f[::-1, ::-1]
            im = Image.fromarray(np.ascontiguousarray(f[y0:y1, x0:x1])).resize((PANEL, PANEL), Image.LANCZOS)
            out.append(np.asarray(im).astype(np.float32))
        self.fr = np.stack(out)

    def at(self, t):
        kf = np.interp(t, self.ts, np.arange(len(self.ts)))
        a = int(np.floor(kf)); b = min(a + 1, len(self.fr) - 1); x = kf - a
        return self.fr[a] * (1 - x) + self.fr[b] * x


def arena_crop():
    """Overhead (rot180) crop box: fit COP (taxels) -> body centroid (px) over the session, map the 128x128 grid."""
    ts = SQ.cam_ts[1]
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", os.path.join(DATA, "camera_1_20260224_160255.mp4"), "-vf",
                          "scale=960:540", "-f", "rawvideo", "-pix_fmt", "gray", "-"], capture_output=True, check=True).stdout
    V = np.frombuffer(raw, np.uint8).reshape(-1, 540, 960)[:, ::-1, ::-1]
    n = min(len(V), len(ts)); bg = np.median(V[np.linspace(0, n - 1, 60).astype(int)], axis=0)
    cam, cop = [], []
    for i in range(0, n, 3):
        m = ndi.binary_opening((V[i].astype(np.int16) - bg) > 45, iterations=4); lab, k = ndi.label(m)
        if k == 0:
            continue
        s = ndi.sum(m, lab, range(1, k + 1)); j = int(np.argmax(s)) + 1
        if s[j - 1] < 800:
            continue
        yy, xx = np.nonzero(lab == j)
        P = SQ.frame(ts[i]); A = np.where(P > THRESHOLD, P, 0)
        if A.sum() < 5e4:
            continue
        r, c = np.nonzero(A); w = A[r, c]
        cam.append([xx.mean() * 2, yy.mean() * 2]); cop.append([(c * w).sum() / w.sum(), (r * w).sum() / w.sum()])
    cam, cop = np.array(cam), np.array(cop)
    ax = np.polyfit(cop[:, 0], cam[:, 0], 1); ay = np.polyfit(cop[:, 1], cam[:, 1], 1)
    x0, x1 = sorted(np.polyval(ax, [-4, 132])); y0, y1 = sorted(np.polyval(ay, [-4, 132]))
    side = max(x1 - x0, y1 - y0); cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    box = [int(cx - side / 2), int(cy - side / 2), int(cx + side / 2), int(cy + side / 2)]
    print("overhead crop", box, "scale px/taxel", ax[0], ay[0], flush=True)
    return box


# tactile floor painter for the 128x128 grid
s_ = PANEL / 128
jj, ii = np.meshgrid(np.arange(PANEL), np.arange(PANEL))
COL = np.clip((jj / s_).astype(int), 0, 127); ROW = np.clip((ii / s_).astype(int), 0, 127)
CELL = ((jj / s_ - COL) < (1 - 1.0 / s_)) & ((ii / s_ - ROW) < (1 - 1.0 / s_))


def floor(P):
    out = np.where(CELL[..., None], np.array([30, 32, 42], np.float32), np.array([8, 9, 13], np.float32))
    act = np.clip((P - THRESHOLD) / 2000, 0, 1); h = np.clip(gaussian_filter(act, 1.6) * 1.8, 0, 1)
    out = out + h[ROW, COL][..., None] * np.array([255, 120, 30], np.float32) * 0.55
    rgb, al = pressure_rgba(P); A = np.clip(al * 1.4, 0, 1)[ROW, COL][..., None]
    cell = np.where(CELL[..., None], rgb[ROW, COL], 12.0)
    return out * (1 - A) + cell * A


CAMS = {}


def title(t):
    im = to_img(blank()).convert("RGBA"); a = ease(t / 0.6)
    text_block(im, (W / 2, 330), ["Supplementary Video 5"], 30, "Medium", fill=EMBER, anchor="ma", alpha=a)
    text_block(im, (W / 2, 390), ["Reconfiguration of the sensor modules", "into an open-field arena"], 60, "SemiBold", anchor="ma", alpha=a)
    text_block(im, (W / 2, 570), ["Four 64 × 64 modules tiled 2 × 2: a 256 × 256 mm floor of 128 × 128 taxels."],
               32, "Regular", fill=(210, 204, 220), anchor="ma", alpha=ease((t - 0.6) / 0.6))
    return im


def square(t):
    if not CAMS:
        CAMS["top"] = Cam(1, (617, 117, 1447, 947), True)  # arena floor in the rotated overhead frame
        CAMS["side"] = Cam(0, (420, 0, 1500, 1080), False)
    tt = T_A + t * SPEED
    f = blank()
    f[Y0:Y0 + PANEL, XS[0]:XS[0] + PANEL] = floor(SQ.frame(tt))
    f[Y0:Y0 + PANEL, XS[1]:XS[1] + PANEL] = CAMS["top"].at(tt)
    f[Y0:Y0 + PANEL, XS[2]:XS[2] + PANEL] = CAMS["side"].at(tt)
    im = to_img(f).convert("RGBA")
    for x, lab in zip(XS, ["Tactile floor (128 × 128 taxels)", "Overhead camera", "Side camera"]):
        text_block(im, (x, Y0 - 50), [lab], 30, "Medium")
    badge(im, "Single rat · 128 × 128 taxels", (XS[0] + 4, 60))
    text_block(im, (W - 40, 64), [f"24 February 2026, rat 4 · M = 200, T = 700 · 0.75× speed · t = {tt:5.1f} s"], 24,
               fill=(170, 162, 182), anchor="ra")
    caption(im, t, [(0.3, 7.6, "Four modules tiled 2 × 2 form a square open-field arena, recorded with the same readout settings as the runway."),
                    (7.8, 15.9, "Paw contacts are recorded across the arena during walking, turning and rearing.")], 0)
    return im


MULTI = {}


def multi(t):
    if "v" not in MULTI:
        # cropped below the recording's own panel titles; panel height matches the single-rat segment
        MULTI["v"] = read_video(os.path.join(SOURCES, "arena_three_rats.mov"), 22, 20, 30, 1254, crop=(1920, 904, 0, 156))
    fr = MULTI["v"]; k = min(len(fr) - 1, int(t * 30))
    im = to_img(blank()).convert("RGBA")
    clip = Image.fromarray(fr[k]); x0 = (W - clip.width) // 2
    arena_panels(im, clip, x0, Y0)
    badge(im, "Three rats · 128 × 128 taxels", (x0 + 4, 60))
    caption(im, t, [(0.3, 9.7, "Three rats explore the arena simultaneously; the contacts of all animals are recorded concurrently."),
                    (9.9, 19.7, "No markers, tethers or body-mounted sensors are required.")], 0)
    return im


SEGMENTS = [(title, 4.0), (square, (T_B - T_A) / SPEED), (multi, 20.0)]


def main(out):
    w = Writer(out, W, H, FPS, crf=20, preset="medium")
    for fn, dur in SEGMENTS:
        n = int(round(dur * FPS))
        for k in range(n):
            t = k / FPS
            fr = to_arr(fn(t)); edge = min(t, dur - t)
            if edge < 0.25:
                fr = fr * ease(edge / 0.25)
            w.add(fr)
        print(fn.__name__, "done", flush=True)
    w.close()
    poster(out, out.replace(".mp4", ".jpg"), t=12.0)
    print("wrote", out)


if __name__ == "__main__":
    if os.environ.get("STILL"):
        name, tt = os.environ["STILL"].split(":")
        fn = dict((f.__name__, f) for f, _ in SEGMENTS)[name]
        fn(float(tt)).convert("RGB").save(os.path.join(WORK, "shots", f"s5_{name}_{tt}.jpg"), quality=88)
    else:
        main(sys.argv[1])
