"""Hero loop for the website: the overhead camera view of the runway, rectified to sensor coordinates, with
each taxel above threshold glowing where the rat presses (crisp 2 mm taxels) and a fading footprint trail.
Usage: python make_hero.py <out.mp4> [t_start t_end slow width]"""
import sys, os, json, numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ta_frames import Runway
from ta_register import Rectifier, read_range
from media_common import WORK, Writer, pressure_rgba, draw_text, poster
from scipy.ndimage import gaussian_filter
from PIL import Image

out = sys.argv[1]
t_a, t_b = (float(sys.argv[2]), float(sys.argv[3])) if len(sys.argv) > 3 else (33.55, 36.35)
slow = float(sys.argv[4]) if len(sys.argv) > 4 else 0.25
OUT_W = int(sys.argv[5]) if len(sys.argv) > 5 else 1920
FPS = 30
U0, U1, V0, V1 = -4, 260, -5, 69  # sensor-space view (taxels): full 256-taxel length, a little margin

rw = Runway(os.path.join(WORK, "cache", "rat4_0224.npz"))
Hc = np.array(json.load(open(os.path.join(WORK, "cache", "rat4_0224_selfcal.json")))["H_rot180px_to_taxel"])
s = OUT_W / (U1 - U0)
rect = Rectifier(Hc, s=s, u0=U0, u1=U1, v0=V0, v1=V1)
OUT_H = rect.Hh - (rect.Hh % 2)
video = os.path.join(WORK, "data", "rat4_0224", "camera_1_20260224_163907.mp4")
cts = rw.cam_ts[1]
k0 = max(int(np.searchsorted(cts, t_a)) - 2, 0); k1 = min(int(np.searchsorted(cts, t_b)) + 2, len(cts) - 1)
raw = read_range(video, k0, k1 - k0 + 1)


def grade(f):  # neutral, dim camera with compressed highlights so the touch signal carries the colour
    f = f.astype(np.float32)
    g = f.mean(axis=2, keepdims=True)
    f = (g + 0.2 * (f - g)) / 255.0
    f = np.clip((f - 0.27) / 0.73, 0, 1)  # floor (measured 0.20-0.31) -> near black
    return 12 + 165 * f / (f + 0.3) * 1.3   # soft roll-off: fur tops out around mid-grey


cam = np.stack([grade(rect.warp(f)) for f in raw])[:, :OUT_H]
print("camera frames", len(cam), cam.shape)

# per-pixel taxel lookup for crisp taxels with a 1 px gap
jj, ii = np.meshgrid(np.arange(rect.W), np.arange(OUT_H))
u = U0 + jj / s; v = V0 + ii / s
col = np.floor(u).astype(int); row = np.floor(v).astype(int)
valid = (col >= 0) & (col < 256) & (row >= 0) & (row < 64)
gap = ((u - np.floor(u)) < (1 - 1.2 / s)) & ((v - np.floor(v)) < (1 - 1.2 / s))
colc = np.clip(col, 0, 255); rowc = np.clip(row, 0, 63)

n_out = int(round((t_b - t_a) / slow * FPS))
dt = slow / FPS
decay = np.exp(-dt / 0.9)  # footprints fade over about a second of real time
fade = int(0.3 * FPS)
GLOW = np.array([255, 120, 30], np.float32)
TRAIL_RGB = np.array([170, 40, 120], np.float32)


def compose(t, trail):
    kf = np.interp(t, cts[k0:k1 + 1], np.arange(k0, k1 + 1)) - k0
    a = int(np.floor(kf)); b = min(a + 1, len(cam) - 1); x = kf - a
    base = cam[a] * (1 - x) + cam[b] * x
    P = rw.frame(t)
    trail = np.maximum(trail * decay, np.where(P > 700, P, 0).astype(np.float32))
    # soft halo around current contacts (additive), computed at taxel resolution then looked up
    act = np.clip((P.astype(np.float32) - 700) / 2000, 0, 1)
    halo = gaussian_filter(act, 1.6) * 1.8
    base = base + (np.clip(halo, 0, 1)[rowc, colc] * valid)[..., None] * GLOW * 0.55
    # fading trail: dim taxels, then current contacts: opaque taxels on a dark grid
    tx = np.clip((trail - 700) / 2500, 0, 1)
    A = ((np.where(trail > 700, 0.25 + 0.35 * tx, 0) * (P <= 700))[rowc, colc] * valid)[..., None]
    base = base * (1 - A) + TRAIL_RGB * A  # footprints just left: dim magenta
    rgb, al = pressure_rgba(P)
    A = (np.clip(al * 1.4, 0, 1)[rowc, colc] * valid)[..., None]
    cell = np.where(gap[..., None], rgb[rowc, colc], 12.0)
    base = base * (1 - A) + cell * A
    return base, trail


if os.environ.get("STILL"):
    from PIL import Image
    trail = np.zeros((64, 256), np.float32)
    ts = [float(x) for x in os.environ["STILL"].split(",")]
    rows = []
    tt = t_a
    for tgt in ts:
        while tt < tgt:
            _, trail = compose(tt, trail); tt += dt
        f, trail = compose(tt, trail); rows.append(f)
    Image.fromarray(np.clip(np.vstack(rows), 0, 255).astype(np.uint8)).save(out.replace(".mp4", "_still.jpg"), quality=90)
    sys.exit(0)

w = Writer(out, rect.W, OUT_H, FPS, crf=21)
trail = np.zeros((64, 256), np.float32)
for n in range(n_out):
    base, trail = compose(t_a + n * dt, trail)
    k = min(n, n_out - 1 - n)
    if k < fade:
        base = base * (0.45 + 0.55 * k / fade)
    w.add(base)
w.close()
img = Image.fromarray(np.zeros((10, 10, 3), np.uint8))
poster(out, out.replace(".mp4", ".jpg"), t=(n_out / FPS) * 0.45)
print("wrote", out, n_out, "frames", rect.W, "x", OUT_H)
