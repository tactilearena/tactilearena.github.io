"""Loops of what the readout boards actually read, packet by packet, from a real recording.
Each output frame is one board frame (about 1 ms): black = not read in that frame, grey = read and below
threshold, colour = read and above threshold.
  module mode: one 64x64 module, square (for the home page card)
  runway mode: all four modules, 64x256 strip (for How it works and the overview video)
Usage: python make_sampling.py module|runway out.mp4 [t0 n_frames board]"""
import sys, os, numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from PIL import Image
from ta_frames import Runway
from media_common import WORK, Writer, pressure_rgba, draw_text, poster, THRESHOLD

mode, out = sys.argv[1], sys.argv[2]
t0 = float(sys.argv[3]) if len(sys.argv) > 3 else 34.95
n_frames = int(sys.argv[4]) if len(sys.argv) > 4 else 300
board = int(sys.argv[5]) if len(sys.argv) > 5 else 2   # left-to-right module index for module mode
rw = Runway(os.path.join(WORK, "cache", "rat4_0224.npz"))
UNREAD, READ = np.array([10, 8, 14], np.float32), np.array([62, 66, 84], np.float32)


def module_state(k, p):
    bd = rw.boards[k]
    a, b = bd["off"][p], bd["off"][p + 1]
    val = np.zeros(4096, np.float32); read = np.zeros(4096, bool)
    val[bd["rc"][a:b]] = bd["val"][a:b]; read[bd["rc"][a:b]] = True
    return val.reshape(64, 64), read.reshape(64, 64), b - a


def paint(val, read, s, gap=1):
    rgb = np.where(read[..., None], READ, UNREAD)
    c, al = pressure_rgba(val)
    al = np.where(val > THRESHOLD, np.clip(al * 1.5, 0, 1), 0)[..., None]
    rgb = rgb * (1 - al) + c * al
    up = np.repeat(np.repeat(rgb, s, 0), s, 1)
    m = np.ones((s, s), bool); m[-gap:, :] = False; m[:, -gap:] = False
    cell = np.tile(m, read.shape)
    return np.where(cell[..., None], up, 4.0)


if mode == "module":
    s = 8; W = H = 64 * s
    bd = rw.boards[board]
    p0 = int(np.searchsorted(bd["ts"], t0))
    w = Writer(out, W, H, fps=15, crf=20)
    for i in range(n_frames):
        val, read, n = module_state(board, p0 + i)
        w.add(paint(val, read, s))
    w.close()
else:
    s = 7; W = 256 * s; top = 64; H = 64 * s + top + 8
    p0 = [int(np.searchsorted(bd["ts"], t0)) for bd in rw.boards]
    w = Writer(out, W, H, fps=15, crf=20)
    for i in range(n_frames):
        canvas = np.zeros((H, W, 3), np.float32); canvas[:] = (8, 6, 12)
        tot = 0; above = 0
        for k in range(4):
            val, read, n = module_state(k, p0[k] + i)
            tot += n; above += int((val > THRESHOLD).sum())
            canvas[top:top + 64 * s, 64 * s * k:64 * s * (k + 1)] = paint(val, read, s)
        im = Image.fromarray(np.clip(canvas, 0, 255).astype(np.uint8))
        t = rw.boards[0]["ts"][p0[0] + i]
        draw_text(im, (12, 18), f"Board frame {i + 1:>3}   t = {t:7.3f} s", size=26, mono=True, fill=(230, 226, 236))
        draw_text(im, (W - 12, 18), f"taxels read this frame: {tot:,} of 16,384 ({100 * tot / 16384:.1f}%)", size=26,
                  mono=True, fill=(255, 179, 138), anchor="ra")
        w.add(np.asarray(im))
    w.close()
poster(out, out.replace(".mp4", ".jpg"), t=2.0)
print("wrote", out)
