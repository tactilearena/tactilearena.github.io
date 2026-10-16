"""Shared look for TactileArena website and video media: colours, fonts, pressure colouring, ffmpeg output."""
import os, subprocess, numpy as np
from PIL import Image, ImageDraw, ImageFont
from matplotlib import colormaps

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
WORK = os.path.join(REPO, ".work")
FONT_VF = os.path.join(WORK, "fonts", "IBMPlexSans-VF.ttf")
FONT_MONO = os.path.join(WORK, "fonts", "IBMPlexMono-Regular.ttf")

# Colours (sRGB 0-255). Paws follow the paper's trajectory figure: FL blue, FR orange, HL green, HR pink.
INK = (12, 14, 20)
PAPER = (246, 245, 241)
ACCENT = (255, 138, 36)       # warm orange: "touch"
MUTED = (150, 156, 170)
PAW = {"FL": (77, 163, 255), "FR": (255, 154, 60), "HL": (61, 220, 132), "HR": (255, 95, 162)}
PAW_NAME = {"FL": "left fore", "FR": "right fore", "HL": "left hind", "HR": "right hind"}

THRESHOLD = 700  # firmware threshold in the paper's recordings (raw ADC units)
_LUT = (colormaps["inferno"](np.linspace(0, 1, 256))[:, :3] * 255).astype(np.float32)


def font(size, weight="Regular", mono=False):
    if mono:
        return ImageFont.truetype(FONT_MONO, size)
    f = ImageFont.truetype(FONT_VF, size)
    f.set_variation_by_name(weight.encode() if isinstance(weight, str) else weight)
    return f


def pressure_rgba(P, lo=THRESHOLD, hi=3600, gamma=0.75):
    """Raw taxel values -> (rgb float 0-255, alpha 0-1). Below threshold is transparent."""
    x = np.clip((P.astype(np.float32) - lo) / (hi - lo), 0, 1) ** gamma
    idx = (0.25 + 0.75 * x) * 255  # start the ramp at deep purple, not black
    rgb = _LUT[idx.astype(np.int32)]
    a = np.where(P > lo, 0.35 + 0.65 * np.clip(x * 1.6, 0, 1), 0.0).astype(np.float32)
    return rgb, a


def taxel_upsample(img, s, gap=1):
    """Nearest-neighbour upsample of a (rows, cols[, c]) taxel image to s px per taxel, with a gap line
    between taxels (returned as a 0/1 mask) so individual 2 mm taxels stay visible."""
    up = np.repeat(np.repeat(img, s, axis=0), s, axis=1)
    if gap <= 0:
        return up, None
    m = np.ones((s, s), np.float32); m[-gap:, :] = 0; m[:, -gap:] = 0
    tile = np.tile(m, (img.shape[0], img.shape[1]))
    return up, tile


def place(canvas_shape, img, r0, c0):
    """Paste a (h, w[, c]) array into a zero canvas at (r0, c0), clipping at the edges."""
    out = np.zeros(canvas_shape[:2] + img.shape[2:], img.dtype)
    H, W = canvas_shape[:2]; h, w = img.shape[:2]
    rr0, cc0 = max(r0, 0), max(c0, 0); rr1, cc1 = min(r0 + h, H), min(c0 + w, W)
    if rr1 > rr0 and cc1 > cc0:
        out[rr0:rr1, cc0:cc1] = img[rr0 - r0:rr1 - r0, cc0 - c0:cc1 - c0]
    return out


class Writer:
    """Pipe RGB frames into an H.264 MP4 (web-friendly: yuv420p, faststart)."""

    def __init__(self, path, w, h, fps=30, crf=20, preset="slow", audio=None):
        os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
        cmd = ["ffmpeg", "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{w}x{h}",
               "-r", str(fps), "-i", "-"]
        if audio:
            cmd += ["-i", audio, "-c:a", "aac", "-b:a", "160k", "-shortest"]
        cmd += ["-c:v", "libx264", "-preset", preset, "-crf", str(crf), "-pix_fmt", "yuv420p",
                "-movflags", "+faststart", path]
        self.p = subprocess.Popen(cmd, stdin=subprocess.PIPE)
        self.w, self.h, self.n = w, h, 0

    def add(self, frame):
        f = np.ascontiguousarray(np.clip(frame, 0, 255).astype(np.uint8))
        assert f.shape == (self.h, self.w, 3), f.shape
        self.p.stdin.write(f.tobytes()); self.n += 1

    def close(self):
        self.p.stdin.close(); self.p.wait()
        return self.n


def poster(mp4, jpg, t=0.0, width=None):
    vf = ["-vf", f"scale={width}:-2"] if width else []
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-ss", str(t), "-i", mp4, "-frames:v", "1", *vf, "-q:v", "3", jpg],
                   check=True)


def draw_text(img, xy, text, size=32, weight="Regular", fill=(255, 255, 255), anchor="la", mono=False, shadow=False):
    d = ImageDraw.Draw(img)
    f = font(size, weight, mono)
    if shadow:
        d.text((xy[0] + 2, xy[1] + 2), text, font=f, fill=(0, 0, 0), anchor=anchor)
    d.text(xy, text, font=f, fill=fill, anchor=anchor)
    return d.textbbox(xy, text, font=f, anchor=anchor)
