"""Two stacked, synchronised views of one walking bout: the overhead camera (top) and the tactile floor on
its own (bottom), both in sensor coordinates, with automatic paw-identity tags from the analysis pipeline.
Usage: python make_camera_floor.py out.mp4 [t_start t_end slow width]"""
import sys, os, numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from PIL import Image
from ta_scene import Session, TaxelView, paw_tags
from media_common import Writer, poster, draw_text

out = sys.argv[1]
t_a, t_b = (float(sys.argv[2]), float(sys.argv[3])) if len(sys.argv) > 3 else (33.75, 36.05)
slow = float(sys.argv[4]) if len(sys.argv) > 4 else 0.25
W = int(sys.argv[5]) if len(sys.argv) > 5 else 1920
FPS = 30
S = Session()
view = TaxelView.fit(W)
S.load_camera(t_a, t_b, view)
H = 2 * view.H + 8
n_out = int(round((t_b - t_a) / slow * FPS)); dt = slow / FPS
fade = int(0.3 * FPS)
lab = max(18, int(W / 80))


def frame(t):
    P = S.rw.frame(t)
    cam = S.camera(t)
    flo = view.floor(P)
    img = np.zeros((H, W, 3), np.float32)
    img[:view.H] = cam; img[view.H + 8:] = flo
    im = Image.fromarray(np.clip(img, 0, 255).astype(np.uint8))
    steps = S.active_steps(t)
    top = Image.fromarray(np.asarray(im)[:view.H]); paw_tags(top, view, steps, size=lab)
    bot = Image.fromarray(np.asarray(im)[view.H + 8:]); paw_tags(bot, view, steps, size=lab)
    im.paste(top, (0, 0)); im.paste(bot, (0, view.H + 8))
    pad = int(W / 90)
    draw_text(im, (pad, pad), "Overhead camera", size=lab, weight="Medium", fill=(235, 235, 240), shadow=True)
    draw_text(im, (pad, view.H + 8 + pad), "Tactile floor: 64 × 256 taxels, 2 mm pitch", size=lab,
              weight="Medium", fill=(235, 235, 240), shadow=True)
    draw_text(im, (W - pad, H - pad), f"{slow:g}× speed", size=int(lab * 0.8), fill=(170, 172, 182),
              anchor="rd")
    return np.asarray(im).astype(np.float32)


if os.environ.get("STILL"):
    Image.fromarray(frame(float(os.environ["STILL"])).astype(np.uint8)).save(out.replace(".mp4", "_still.jpg"), quality=90)
    sys.exit(0)
w = Writer(out, W, H, FPS, crf=22)
for n in range(n_out):
    f = frame(t_a + n * dt)
    k = min(n, n_out - 1 - n)
    if k < fade:
        f = f * (0.45 + 0.55 * k / fade)
    w.add(f)
w.close()
poster(out, out.replace(".mp4", ".jpg"), t=n_out / FPS * 0.5)
print("wrote", out, n_out, "frames", W, "x", H)
