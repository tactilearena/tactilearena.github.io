"""The TactileArena overview video (1920x1080, 30 fps, on-screen captions, no narration).
Every moving image is from a real recording (2026-02-24, rat 4, runway) or the manuscript's figures, except the
one-module sampling animation, which runs the readout firmware's sampling loop on a simulated paw.
Writes docs/assets/video/overview.mp4, overview.jpg, overview.vtt (captions) and .work/overview_script.md.
Usage: python make_overview.py            full render
       STILL=<scene>:<t> python make_overview.py   one frame of one scene to .work/shots/"""
import os, sys, json, subprocess, numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from PIL import Image, ImageDraw, ImageFilter
from scipy.interpolate import PchipInterpolator
from scipy import ndimage as ndi
from ta_scene import Session, TaxelView, paw_tags
from media_common import (REPO, WORK, Writer, font, pressure_rgba, draw_text, PAW, THRESHOLD, poster)

W, H, FPS = 1920, 1080, 30
A = os.path.join(REPO, "docs", "assets")
BG = np.array([10, 7, 15], np.float32)
EMBER = (255, 179, 138)
S = Session()


# ------------------------------------------------------------------ helpers
def blank():
    f = np.empty((H, W, 3), np.float32); f[:] = BG; return f


def to_img(f):
    return Image.fromarray(np.clip(f, 0, 255).astype(np.uint8))


def to_arr(im):
    return np.asarray(im.convert("RGB")).astype(np.float32)


def ease(x):
    x = min(max(x, 0.0), 1.0); return x * x * (3 - 2 * x)


def alpha_in_out(t, t0, t1, fade=0.35):
    if t < t0 or t > t1:
        return 0.0
    return min(ease((t - t0) / fade), ease((t1 - t) / fade))


def text_block(im, xy, lines, size, weight="Regular", fill=(255, 255, 255), anchor="la", spacing=1.3, alpha=1.0):
    """Draw lines of text; returns bottom y. Alpha is applied by blending a layer."""
    layer = Image.new("RGBA", im.size, (0, 0, 0, 0)); d = ImageDraw.Draw(layer)
    f = font(size, weight); x, y = xy
    for ln in lines:
        d.text((x, y), ln, font=f, fill=fill + (int(255 * alpha),), anchor=anchor)
        y += size * spacing
    im.alpha_composite(layer) if im.mode == "RGBA" else im.paste(layer, (0, 0), layer)
    return y


def wrap(text, size, weight, width):
    f = font(size, weight); words = text.split(); lines = []; cur = ""
    for w_ in words:
        t = (cur + " " + w_).strip()
        if f.getlength(t) <= width:
            cur = t
        else:
            lines.append(cur); cur = w_
    if cur:
        lines.append(cur)
    return lines


CAPTIONS = []  # (global start, end, text) for the VTT


def caption(im, t, items, scene_t0):
    """Lower-third caption: items = [(t0, t1, text)] in scene time."""
    for t0, t1, txt in items:
        a = alpha_in_out(t, t0, t1)
        if a <= 0:
            continue
        lines = wrap(txt, 40, "Medium", 1500)
        f = font(40, "Medium")
        widths = [f.getlength(l) for l in lines]
        bw = max(widths) + 70; bh = 40 * 1.35 * len(lines) + 34
        x0 = (W - bw) / 2; y0 = H - 36 - bh
        layer = Image.new("RGBA", im.size, (0, 0, 0, 0)); d = ImageDraw.Draw(layer)
        d.rounded_rectangle([x0, y0, x0 + bw, y0 + bh], radius=14, fill=(22, 15, 30, int(225 * a)), outline=(70, 58, 84, int(200 * a)), width=2)
        y = y0 + 17
        for l, wl in zip(lines, widths):
            d.text((W / 2, y), l, font=f, fill=(245, 242, 248, int(255 * a)), anchor="ma"); y += 40 * 1.35
        im.paste(layer, (0, 0), layer)


def badge(im, text, xy=(40, 36), alpha=1.0):
    layer = Image.new("RGBA", im.size, (0, 0, 0, 0)); d = ImageDraw.Draw(layer)
    f = font(26, "SemiBold"); bb = d.textbbox(xy, text, font=f)
    d.rounded_rectangle([bb[0] - 14, bb[1] - 8, bb[2] + 14, bb[3] + 8], radius=20, fill=(10, 6, 14, int(210 * alpha)),
                        outline=EMBER + (int(120 * alpha),), width=2)
    d.text(xy, text, font=f, fill=EMBER + (int(255 * alpha),))
    im.paste(layer, (0, 0), layer)


def fit_image(path, box_w, box_h, bg=None):
    im = Image.open(path)
    if im.mode == "RGBA":
        base = Image.new("RGBA", im.size, tuple(int(x) for x in (bg if bg is not None else BG)) + (255,))
        im = Image.alpha_composite(base, im)
    im = im.convert("RGB")
    s = min(box_w / im.width, box_h / im.height)
    return im.resize((int(im.width * s), int(im.height * s)), Image.LANCZOS)


def read_video(path, start, dur, fps, scale_w, crop=None):
    """Frames of a clip, resampled to fps, optionally cropped (w, h, x, y) and scaled to scale_w wide (rgb arrays)."""
    if crop:
        w0, h0 = crop[0], crop[1]
    else:
        probe = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
                                "stream=width,height", "-of", "csv=p=0", path],
                               capture_output=True, text=True).stdout.strip().splitlines()[0].split(",")
        w0, h0 = int(probe[0]), int(probe[1])
    sh = int(round(h0 * scale_w / w0 / 2) * 2)
    vf = (f"crop={crop[0]}:{crop[1]}:{crop[2]}:{crop[3]}," if crop else "") + f"fps={fps},scale={scale_w}:{sh}"
    raw = subprocess.run(["ffmpeg", "-v", "error", "-ss", str(start), "-t", str(dur), "-i", path, "-vf",
                          vf, "-f", "rawvideo", "-pix_fmt", "rgb24", "-"],
                         capture_output=True, check=True).stdout
    return np.frombuffer(raw, np.uint8).reshape(-1, sh, scale_w, 3)


# ------------------------------------------------------------------ pressure renderers
class Hero:
    """Camera in sensor coordinates with glowing taxels and a fading footprint trail."""

    def __init__(self, t_a, t_b, width=1920):
        self.view = TaxelView.fit(width)
        S.load_camera(t_a, t_b, self.view)
        self.cam = (S._cam, S._k0, S._k1)
        self.trail = np.zeros((64, 256), np.float32); self.last = None

    def frame(self, t):
        S._cam, S._k0, S._k1 = self.cam
        v = self.view
        if self.last is None or t < self.last:
            self.trail[:] = 0; self.last = t - 0.01
        tt = self.last
        while tt < t:   # integrate the trail at ~240 Hz between output frames
            tt = min(t, tt + 1 / 240)
            P = S.rw.frame(tt)
            self.trail = np.maximum(self.trail * np.exp(-1 / 240 / 0.9), np.where(P > THRESHOLD, P, 0).astype(np.float32))
        self.last = t
        base = S.camera(t); P = S.rw.frame(t)
        tx = np.clip((self.trail - THRESHOLD) / 2500, 0, 1)
        Al = ((np.where(self.trail > THRESHOLD, 0.25 + 0.35 * tx, 0) * (P <= THRESHOLD))[v.row, v.col] * v.valid)[..., None]
        base = base * (1 - Al) + np.array([170, 40, 120], np.float32) * Al
        return v.overlay(base, P)


def calib():
    c = json.load(open(os.path.join(REPO, "data", "calibration_0_450", "calibration_0_450.json")))["boards"]
    out = {}
    for name, b in c.items():
        x = np.asarray(b["pixel_sum_knots"], float); y = np.asarray(b["force_g_knots"], float)
        out[name] = (PchipInterpolator(x, y), x[0], x[-1])
    return out


CAL = calib()


def grams(pixel_sum, col):
    f, lo, hi = CAL["board%d" % [4, 3, 2, 1][min(3, max(0, int(col) // 64))]]
    return 0.0 if pixel_sum < lo else (float(f(min(pixel_sum, hi))))


def paw_traces(t_a, t_b, rate=500):
    """Mass-equivalent load per paw: pressure in the contact(s) nearest each automatic stance event."""
    ts = np.arange(t_a, t_b, 1 / rate); tr = {k: np.full(len(ts), np.nan) for k in PAW}
    for i, t in enumerate(ts):
        P = S.rw.frame(t); m = ndi.binary_dilation(P > THRESHOLD, iterations=1)
        lab, n = ndi.label(m)
        if n == 0:
            continue
        cents = ndi.center_of_mass(m, lab, range(1, n + 1))
        for s in S.active_steps(t):
            d = [np.hypot(c[1] - (s["x"] - 1), c[0] - (s["y"] - 1)) for c in cents]
            sel = [j + 1 for j, dd in enumerate(d) if dd < 9]
            if not sel:
                continue
            tot = float(P[np.isin(lab, sel)].sum())
            g = grams(tot, s["x"] - 1)
            tr[s["label"]][i] = g if np.isnan(tr[s["label"]][i]) else tr[s["label"]][i] + g
    for k in tr:
        tr[k] = np.nan_to_num(tr[k], nan=0.0)
    return ts, tr


# ------------------------------------------------------------------ firmware sampling (one module)
ORDER = json.load(open(os.path.join(A, "data", "scan_order.json")))
PADS = [[0, 0, 2.0, 1.0], [3.3, -2.6, 0.95, 0.75], [4.4, -0.9, 0.95, 0.85], [4.4, 0.9, 0.95, 0.85],
        [3.3, 2.6, 0.95, 0.75], [-2.4, 0, 1.6, 0.55]]


def stamp(truth, x, y, ang, amp):
    rr, cc = np.mgrid[0:64, 0:64]
    for px0, py0, s, a in PADS:
        px = x + px0 * np.cos(ang) - py0 * np.sin(ang); py = y + px0 * np.sin(ang) + py0 * np.cos(ang)
        truth += a * amp * np.exp(-((cc - px) ** 2 + (rr - py) ** 2) / (2 * s * s))


class Sampler:
    def __init__(self):
        self.R = np.array(ORDER["rows"]); self.C = np.array(ORDER["cols"]); self.ox = self.oy = 0; self.centres = []

    def frame(self, truth, M=200, thr=THRESHOLD):
        read = np.zeros((64, 64), bool); log = []; nxt = []

        def take(r, c, phase):
            read[r, c] = True; log.append((r, c, phase, truth[r, c]))

        def neigh(cr, cc, orig):
            if orig and (cr, cc) not in nxt and len(nxt) < 50:
                nxt.append((cr, cc))
            for dc in (0, -1, 1):
                c = cc + dc
                if c < 0 or c >= 64:
                    continue
                for r in (cr - 1, cr, cr + 1):
                    if r < 0 or r >= 64:
                        continue
                    if len(log) >= M:
                        return
                    if read[r, c]:
                        continue
                    take(r, c, "zoom")
                    if len(log) >= M:
                        return
                    if truth[r, c] > thr:
                        neigh(r, c, False)
                        if len(log) >= M:
                            return

        def visit(r, c, phase):
            if read[r, c]:
                return True
            take(r, c, phase)
            if len(log) >= M:
                return False
            if truth[r, c] > thr:
                neigh(r, c, True)
                if len(log) >= M:
                    return False
            return True

        for r, c in self.centres:
            if len(log) >= M or not visit(r, c, "follow"):
                break
        i = 0
        while len(log) < M and i < 4096:
            if not visit((self.R[i] + self.ox) % 64, (self.C[i] + self.oy) % 64, "scan"):
                break
            i += 1
        self.oy += 1
        if self.oy >= 64:
            self.oy = 0; self.ox = (self.ox + 1) % 64
        self.centres = nxt
        return log


def paint_module(truth_or_val, read, s, thr=THRESHOLD, show_unread_truth=False, recent=None):
    unread = np.array([14, 10, 19], np.float32); rd = np.array([70, 74, 94], np.float32)
    rgb = np.where(read[..., None], rd, unread)
    c, al = pressure_rgba(truth_or_val)
    al = np.where((truth_or_val > thr) & read, np.clip(al * 1.5, 0, 1), 0)[..., None]
    rgb = rgb * (1 - al) + c * al
    if recent is not None:
        rgb = np.where(recent[..., None], np.array([255, 255, 255], np.float32), rgb)
    up = np.repeat(np.repeat(rgb, s, 0), s, 1)
    m = np.ones((s, s), bool); m[-1:, :] = False; m[:, -1:] = False
    return np.where(np.tile(m, (64, 64))[..., None], up, 5.0)


# ------------------------------------------------------------------ scenes
SCENES = []


def scene(dur):
    def deco(fn):
        SCENES.append((fn.__name__, dur, fn)); return fn
    return deco


OPEN_T0 = 33.55
_hero = {}


@scene(9.0)
def s01_open(t):
    if "r" not in _hero:
        _hero["r"] = Hero(OPEN_T0, OPEN_T0 + 9 * 0.25 + 0.1)
    f = blank(); r = _hero["r"]
    img = r.frame(OPEN_T0 + t * 0.25)
    y0 = (H - img.shape[0]) // 2 + 30
    f[y0:y0 + img.shape[0]] = img
    im = to_img(f).convert("RGBA")
    a = ease((t - 0.8) / 1.0)
    text_block(im, (W / 2, 150), ["We turned the ground into a sensor."], 64, "SemiBold", anchor="ma", alpha=a)
    text_block(im, (W - 40, H - 60), ["Recorded data · 0.25× speed"], 26, "Regular", fill=(180, 172, 190), anchor="ra",
               alpha=ease(t / 1.0))
    return im


@scene(6.5)
def s02_title(t):
    im = to_img(blank()).convert("RGBA")
    a = ease(t / 0.8)
    # gradient name
    f = font(150, "Bold"); txt = "TactileArena"; tw = f.getlength(txt)
    mask = Image.new("L", (W, 220), 0); ImageDraw.Draw(mask).text(((W - tw) / 2, 20), txt, font=f, fill=int(255 * a))
    grad = np.zeros((220, W, 3), np.float32)
    stops = [(0, (252, 255, 164)), (0.32, (249, 142, 9)), (0.58, (226, 84, 43)), (0.8, (188, 55, 84)), (1, (138, 34, 106))]
    xs = (np.arange(W) - (W - tw) / 2) / tw
    for ch in range(3):
        grad[..., ch] = np.interp(xs, [s_[0] for s_ in stops], [s_[1][ch] for s_ in stops])[None, :]
    im.paste(Image.fromarray(grad.astype(np.uint8)), (0, 250), mask)
    b = ease((t - 0.7) / 0.8)
    y = text_block(im, (W / 2, 500), ["Scalable high-density tactile arenas for measuring", "ground-contact forces in freely moving animals"],
                   44, "Medium", anchor="ma", alpha=b)
    c = ease((t - 1.4) / 0.8)
    y = text_block(im, (W / 2, y + 50), ["Weiwen Lu*, Ariel Slepyan*, Pierce Perkins, Alessandro Ascani Orsini,", "Kiara Quinn, Nitish V. Thakor"],
                   32, "Regular", fill=(225, 220, 232), anchor="ma", alpha=c)
    text_block(im, (W / 2, y + 30), ["Johns Hopkins University  ·  Massachusetts Institute of Technology"], 28, "Regular",
               fill=(170, 162, 182), anchor="ma", alpha=c)
    text_block(im, (W / 2, H - 90), ["* Equal contribution"], 22, "Regular", fill=(140, 132, 150), anchor="ma", alpha=c)
    return im


CF_T0, CF_SLOW = 33.75, 0.2
_cf = {}


@scene(11.5)
def s03_camera_floor(t):
    if "v" not in _cf:
        _cf["v"] = TaxelView.fit(1500); S.load_camera(CF_T0, CF_T0 + 11.5 * CF_SLOW + 0.1, _cf["v"])
        _cf["cam"] = (S._cam, S._k0, S._k1)
    v = _cf["v"]; S._cam, S._k0, S._k1 = _cf["cam"]
    tt = CF_T0 + t * CF_SLOW
    P = S.rw.frame(tt); steps = S.active_steps(tt)
    f = blank(); x0 = (W - v.W) // 2; y0 = 22
    top = to_img(S.camera(tt)); paw_tags(top, v, steps, size=26)
    bot = to_img(v.floor(P)); paw_tags(bot, v, steps, size=26)
    f[y0:y0 + v.H, x0:x0 + v.W] = to_arr(top); f[y0 + v.H + 8:y0 + 2 * v.H + 8, x0:x0 + v.W] = to_arr(bot)
    im = to_img(f).convert("RGBA")
    a = 1.0
    text_block(im, (x0 + 20, y0 + 16), ["Overhead camera"], 28, "Medium", alpha=a)
    text_block(im, (x0 + 20, y0 + v.H + 24), ["Tactile floor"], 28, "Medium", alpha=a)
    text_block(im, (W - 40, y0 + 16), ["0.2× speed"], 24, fill=(180, 172, 190), anchor="ra")
    caption(im, t, [(0.3, 4.4, "Viewed from above, the paws of a walking rat are largely hidden beneath its body."),
                    (4.6, 8.4, "The tactile floor records each contact: its location, its duration and the load it bears."),
                    (8.6, 11.3, "Labels indicate automatic paw assignments (FL, FR, HL, HR).")], 0)
    return im


_ph = {}


@scene(16.0)
def s04_platform(t):
    f = blank()
    if "a" not in _ph:
        _ph["a"] = Image.open(os.path.join(A, "photos", "runway_rat_raw.jpg")).convert("RGB")
        _ph["m"] = fit_image(os.path.join(A, "photos", "module.png"), 1200, 720)
        _ph["v"] = read_video(os.path.join(A, "video", "assembly.mp4"), 4, 60, 10, 540)
    im = to_img(f).convert("RGBA")
    if t < 5.2:
        src = _ph["a"]; z = 1.0 + 0.06 * t / 5.2
        cw, ch = src.width / z, src.width / z * H / W
        if ch > src.height:
            ch = src.height; cw = ch * W / H / 1.0
        cx, cy = src.width / 2, src.height / 2
        crop = src.crop((int(cx - cw / 2), int(cy - ch / 2), int(cx + cw / 2), int(cy + ch / 2))).resize((W, H), Image.LANCZOS)
        im.paste(crop, (0, 0))
        caption(im, t, [(0.3, 5.0, "Four 64 × 64 sensor modules form a 512 × 128 mm runway of 16,384 taxels at 2-mm pitch.")], 0)
    elif t < 10.4:
        lt = t - 5.2; m = _ph["m"]; z = 0.92 + 0.08 * lt / 5.2
        mm = m.resize((int(m.width * z), int(m.height * z)), Image.LANCZOS)
        im.paste(mm, ((W - mm.width) // 2, 40 + (760 - mm.height) // 2))
        caption(im, lt, [(0.3, 5.0, "Each module is a flexible electrode array beneath a piezoresistive film, read by a dedicated Teensy-based board.")], 0)
    else:
        lt = t - 10.4; fr = _ph["v"]; k = min(len(fr) - 1, int(lt * 10 * 3))   # 3x speed
        clip = Image.fromarray(fr[k]); bgc = clip.resize((W, int(W * clip.height / clip.width))).filter(ImageFilter.GaussianBlur(30))
        bgc = Image.fromarray((np.asarray(bgc).astype(np.float32) * 0.35).astype(np.uint8))
        im.paste(bgc, (0, (H - bgc.height) // 2))
        cl = clip.resize((int(clip.width * (H - 40) / clip.height), H - 40))
        im.paste(cl, ((W - cl.width) // 2, 20))
        badge(im, "Assembly · 3× speed", (60, 40))
        caption(im, lt, [(0.2, 5.4, "Assembly: sensor connection, array alignment, and application of the piezoresistive film and waterproof cloth.")], 0)
    return im


_sm = {}


def _sim_setup():
    truth0 = np.zeros((64, 64)); rng = np.random.default_rng(1)
    sam = Sampler(); frames = []
    for k in range(70):
        truth = 40 + 90 * rng.random((64, 64))
        x = 14 + 0.45 * k
        stamp(truth, x, 22, 0.0, 3300 * min(1, k / 6))
        stamp(truth, 44, 42, np.pi * 0.95, 3200)
        frames.append((truth, sam.frame(truth)))
    _sm["frames"] = frames


@scene(22.0)
def s05_sampling(t):
    if "frames" not in _sm:
        _sim_setup()
        _sm["rw"] = True
    im = to_img(blank()).convert("RGBA")
    s = 12; mod_x, mod_y = 150, 50
    if t < 11.0:
        # one frame of the firmware, read by read
        truth, log = _sm["frames"][40]
        n_show = int(np.clip((t - 1.0) / 7.0, 0, 1) * len(log))
        read = np.zeros((64, 64), bool); val = np.zeros((64, 64)); recent = np.zeros((64, 64), bool)
        for j, (r, c, ph, v) in enumerate(log[:n_show]):
            read[r, c] = True; val[r, c] = v
            if j >= n_show - 3:
                recent[r, c] = True
        # ghost of the true pressure (what the board cannot see yet)
        ghost = np.where(truth > THRESHOLD, 1.0, 0.0)
        mod = paint_module(val, read, s, recent=recent if n_show < len(log) else None)
        g = np.repeat(np.repeat(ghost, s, 0), s, 1)[..., None]
        mod = np.where((~np.repeat(np.repeat(read, s, 0), s, 1))[..., None] & (g > 0), mod * 0.5 + np.array([60, 30, 70]) * 0.5, mod)
        f = to_arr(im); f[mod_y:mod_y + 64 * s, mod_x:mod_x + 64 * s] = mod; im = to_img(f).convert("RGBA")
        phase = log[n_show - 1][2] if n_show else "follow"
        counts = {p: sum(1 for x in log[:n_show] if x[2] == p) for p in ("follow", "scan", "zoom")}
        tx = mod_x + 64 * s + 90
        text_block(im, (tx, mod_y), ["Single acquisition frame of one module"], 44, "SemiBold")
        text_block(im, (tx, mod_y + 62), [f"taxels measured: {n_show:3d} / 200 of 4,096"], 34, "Regular", fill=EMBER)
        rows = [("follow", "1  Tracking of previous contacts"), ("scan", "2  Coarse-to-fine background scan"),
                ("zoom", "3  Neighbourhood expansion above threshold")]
        y = mod_y + 160
        for key, label in rows:
            on = (key == phase and n_show < len(log))
            col = (255, 255, 255) if on else (150, 142, 162)
            text_block(im, (tx, y), [label], 34, "Medium" if on else "Regular", fill=col)
            text_block(im, (tx + 40, y + 46), [f"{counts[key]} measurement" + ("" if counts[key] == 1 else "s")], 26, fill=(150, 142, 162)); y += 120
        text_block(im, (tx, y + 20), ["Purple shading: applied pressure not yet measured"], 24, fill=(150, 142, 162))
        caption(im, t, [(0.3, 4.6, "Rather than scanning every taxel, each board measures 200 of its 4,096 taxels per frame."),
                        (4.8, 10.8, "Active contacts are tracked, a coarse-to-fine scan monitors the module, and loaded regions are resolved at full density.")], 0)
    else:
        # real recording, all four boards, frame by frame
        lt = t - 11.0
        if "rp" not in _sm:
            _sm["rp"] = [int(np.searchsorted(bd["ts"], 34.95)) for bd in S.rw.boards]
        i = int(lt * 12)   # 12 board frames per second of video, about 1/80 of real time
        s2 = 7; top = 150; f = to_arr(im)
        tot = 0
        for k, bd in enumerate(S.rw.boards):
            p = _sm["rp"][k] + i; a_, b_ = bd["off"][p], bd["off"][p + 1]
            val = np.zeros(4096); rd = np.zeros(4096, bool)
            val[bd["rc"][a_:b_]] = bd["val"][a_:b_]; rd[bd["rc"][a_:b_]] = True; tot += b_ - a_
            f[top:top + 64 * s2, 64 + 64 * s2 * k:64 + 64 * s2 * (k + 1)] = paint_module(val.reshape(64, 64), rd.reshape(64, 64), s2)
        im = to_img(f).convert("RGBA")
        tnow = S.rw.boards[0]["ts"][_sm["rp"][0] + i]
        text_block(im, (64, top - 70), [f"Recorded data   t = {tnow:.3f} s"], 32, "Medium")
        text_block(im, (W - 64, top - 70), [f"measured in this frame: {tot} of 16,384 taxels"], 32, fill=EMBER, anchor="ra")
        text_block(im, (64, top + 64 * s2 + 20), ["black: not measured     grey: measured, below threshold     colour: measured, above threshold"], 26, fill=(160, 152, 172))
        caption(im, lt, [(0.3, 5.6, "Recorded acquisition frames: paw contacts are resolved completely, while unloaded regions are sampled sparsely."),
                         (5.8, 10.8, "Adaptive sampling enables acquisition across 16,384 taxels at approximately 1,000 frames per second.")], 0)
    return im


LD_T0, LD_SLOW = 33.8, 0.15
_ld = {}


@scene(14.0)
def s06_loading(t):
    if "v" not in _ld:
        _ld["v"] = TaxelView.fit(1700)
        _ld["ts"], _ld["tr"] = paw_traces(LD_T0 - 1.2, LD_T0 + 14 * LD_SLOW + 0.1)
    v = _ld["v"]; tt = LD_T0 + t * LD_SLOW
    P = S.rw.frame(tt); steps = S.active_steps(tt)
    f = blank(); x0 = (W - v.W) // 2; y0 = 20
    fl = to_img(v.floor(P)); paw_tags(fl, v, steps, size=26)
    f[y0:y0 + v.H, x0:x0 + v.W] = to_arr(fl)
    im = to_img(f).convert("RGBA"); d = ImageDraw.Draw(im)
    # traces: last 1.2 s of data, scrolling
    gx0, gx1 = 200, W - 110; gy0 = y0 + v.H + 44; row_h = 84; span = 1.2
    ts, tr = _ld["ts"], _ld["tr"]; sel = (ts > tt - span) & (ts <= tt)
    for r_, k in enumerate(["FL", "FR", "HL", "HR"]):
        yb = gy0 + (r_ + 1) * row_h - 10
        d.line([(gx0, yb), (gx1, yb)], fill=(60, 54, 70), width=1)
        d.text((gx0 - 20, yb - 30), k, font=font(28, "SemiBold"), fill=PAW[k], anchor="rm")
        x = gx0 + (ts[sel] - (tt - span)) / span * (gx1 - gx0)
        y = yb - np.clip(tr[k][sel] / 260.0, 0, 1.15) * (row_h - 16)
        if len(x) > 1:
            pts = list(zip(x.tolist(), y.tolist()))
            poly = [(x[0], yb)] + pts + [(x[-1], yb)]
            layer = Image.new("RGBA", im.size, (0, 0, 0, 0)); ImageDraw.Draw(layer).polygon(poly, fill=PAW[k] + (60,))
            im.alpha_composite(layer); d = ImageDraw.Draw(im)
            d.line(pts, fill=PAW[k], width=3)
    d.text((gx1, gy0 - 8), "mass-equivalent load per paw (0–260 g scale), last 1.2 s", font=font(22), fill=(150, 142, 162), anchor="rb")
    caption(im, t, [(0.3, 6.6, "With synchronized video, contacts are assigned to individual paws, correctly identifying 93.3% of 2,469 manually annotated contacts."),
                    (6.8, 13.7, "The load on each paw is then resolved at approximately 1 kHz throughout every stance.")], 0)
    return im


_inj = {}


@scene(22.0)
def s07_injury(t):
    im = to_img(blank()).convert("RGBA"); d = ImageDraw.Draw(im)
    if "d" not in _inj:
        _inj["d"] = fit_image(os.path.join(A, "figures", "fig5d_ratios.jpg"), 1500, 760)
        src = Image.open(os.path.join(A, "figures", "fig5_sni.jpg")); w_, h_ = src.size
        _inj["ab"] = src.crop((0, 0, w_, int(0.2 * h_)))
        _inj["ab"] = fit_image_from(_inj["ab"], 1760, 700)
    if t < 8.0:
        a = ease((t - 0.3) / 0.8)
        text_block(im, (W / 2, 120), ["After sciatic nerve pinch, rats continued to place the injured hindpaw on the ground..."], 40, "Medium", anchor="ma", alpha=a)
        # two bars: change in ratio (start at 1)
        items = [("Duty-factor ratio", 0.33, (150, 142, 162), "timing"), ("Time-integrated loading ratio", 0.59, (242, 107, 58), "touch")]
        bx = 520; bw_ = 300; base_y = 250; full = 470
        for i_, (lab, dec, col, _) in enumerate(items):
            x = bx + i_ * 560
            g = ease((t - 1.5 - 0.6 * i_) / 1.6)
            h1 = full; h2 = full * (1 - dec * g)
            d.rectangle([x, base_y + full - h1, x + bw_, base_y + full], outline=(80, 72, 92), width=3)
            d.rectangle([x, base_y + full - h2, x + bw_, base_y + full], fill=col)
            d.text((x + bw_ / 2, base_y + full + 20), lab, font=font(34, "Medium"), fill=(235, 230, 240), anchor="ma")
            d.text((x + bw_ / 2, base_y + full - h2 - 16), f"−{dec * g:.2f}", font=font(52, "SemiBold"), fill=col, anchor="mb")
        d.text((W / 2, base_y + full + 76), "Change from baseline in the left-to-right hindpaw ratio, days 1–5 after surgery",
               font=font(26), fill=(150, 142, 162), anchor="ma")
        caption(im, t, [(4.5, 7.8, "...but the loading ratio decreased by approximately 60%, nearly twice the decrease in the duty-factor ratio.")], 0)
    elif t < 15.0:
        lt = t - 8.0; fig = _inj["d"]
        card = Image.new("RGB", (fig.width + 40, fig.height + 40), "white"); card.paste(fig, (20, 20))
        im.paste(card, ((W - card.width) // 2, 50))
        caption(im, lt, [(0.3, 3.6, "In three injured and two sham-operated rats followed for two weeks, both ratios decreased and then returned toward baseline."),
                         (3.8, 6.8, "Peak loading of the injured hindpaw decreased by 27%, and that of the contralateral hindpaw increased by 22–23%.")], 0)
    else:
        lt = t - 15.0; fig = _inj["ab"]
        im.paste(fig, ((W - fig.width) // 2, 110))
        caption(im, lt, [(0.3, 6.7, "Contact morphology also changed: injured-hindpaw contacts became smaller and more elongated (cyan outlines).")], 0)
    text_block(im, (W - 40, H - 34), ["Adapted from Fig. 5 of the manuscript."], 22, fill=(130, 122, 142), anchor="rb")
    return im


def fit_image_from(im, bw, bh):
    s = min(bw / im.width, bh / im.height)
    return im.convert("RGB").resize((int(im.width * s), int(im.height * s)), Image.LANCZOS)


_ar = {}


def arena_panels(im, clip, x0, y0, src_w=1920, size=30):
    """Paste a frame of the three-rat arena clip (cropped below its own panel titles) and label its two panels."""
    im.paste(clip, (x0, y0))
    s = clip.width / src_w
    for dx, lab in ((18, "Tactile floor (128 × 128 taxels)"), (922, "Overhead camera")):
        text_block(im, (x0 + int(dx * s), y0 - 50), [lab], size, "Medium")


@scene(10.0)
def s08_beyond(t):
    if "v" not in _ar:
        _ar["v"] = read_video(os.path.join(A, "video", "arena_multi.mp4"), 14, 10, 30, 1500)
    fr = _ar["v"]; k = min(len(fr) - 1, int(t * 30))
    im = to_img(blank()).convert("RGBA")
    clip = Image.fromarray(fr[k]); x0 = (W - clip.width) // 2
    arena_panels(im, clip, x0, 160)
    badge(im, "Three rats · 128 × 128 taxels", (x0 + 14, 34))
    caption(im, t, [(0.3, 4.9, "The modular design allows the same four modules to form other arenas, such as a square open field with three rats."),
                    (5.1, 9.7, "Future applications include integration with pose estimation, neural recordings, contact-triggered perturbations and shear sensing.")], 0)
    return im


@scene(9.0)
def s09_open(t):
    im = to_img(blank()).convert("RGBA")
    a = ease(t / 0.8)
    text_block(im, (W / 2, 250), ["Open resources"], 80, "SemiBold", anchor="ma", fill=(255, 179, 138), alpha=a)
    lines = ["KiCad design files, build guide and assembly video", "Readout firmware and synchronized recording code",
             "Analysis pipeline, pretrained models and calibration curves", "85 runway recordings with annotations"]
    y = 400
    for i_, ln in enumerate(lines):
        y = text_block(im, (W / 2, y), [ln], 42, "Regular", anchor="ma", alpha=ease((t - 0.6 - 0.35 * i_) / 0.6)) + 10
    text_block(im, (W / 2, y + 40), ["Approximately US$550 in parts per four-module runway"], 34, "Regular", fill=(170, 162, 182), anchor="ma",
               alpha=ease((t - 2.4) / 0.6))
    text_block(im, (W / 2, H - 170), ["tactilearena.github.io"], 56, "SemiBold", anchor="ma", alpha=ease((t - 3.0) / 0.6))
    return im


@scene(6.0)
def s10_credits(t):
    im = to_img(blank()).convert("RGBA"); a = ease(t / 0.8)
    y = text_block(im, (W / 2, 300), ["TactileArena"], 64, "SemiBold", anchor="ma", alpha=a)
    y = text_block(im, (W / 2, y + 30), ["Weiwen Lu*, Ariel Slepyan*, Pierce Perkins, Alessandro Ascani Orsini,", "Kiara Quinn, Nitish V. Thakor"],
                   36, anchor="ma", alpha=a)
    y = text_block(im, (W / 2, y + 30), ["Johns Hopkins University  ·  Massachusetts Institute of Technology"], 30,
                   fill=(170, 162, 182), anchor="ma", alpha=a)
    text_block(im, (W / 2, y + 30), ["* Equal contribution"], 24, fill=(140, 132, 150), anchor="ma", alpha=a)
    text_block(im, (W / 2, H - 140), ["Recordings: rat 4, 24 February 2026 (before surgery), unless labelled otherwise."], 24,
               fill=(130, 122, 142), anchor="ma", alpha=a)
    return im


# ------------------------------------------------------------------ captions -> VTT (scene-relative -> global)
CAPTION_TABLE = {
    "s01_open": [(1.0, 8.6, "We turned the ground into a sensor.")],
    "s03_camera_floor": [(0.3, 4.4, "Viewed from above, the paws of a walking rat are largely hidden beneath its body."),
                         (4.6, 8.4, "The tactile floor records each contact: its location, its duration and the load it bears."),
                         (8.6, 11.3, "Labels indicate automatic paw assignments (FL, FR, HL, HR).")],
    "s04_platform": [(0.3, 5.0, "Four 64 × 64 sensor modules form a 512 × 128 mm runway of 16,384 taxels at 2-mm pitch."),
                     (5.5, 10.2, "Each module is a flexible electrode array beneath a piezoresistive film, read by a dedicated Teensy-based board."),
                     (10.6, 15.8, "Assembly: sensor connection, array alignment, and application of the piezoresistive film and waterproof cloth.")],
    "s05_sampling": [(0.3, 4.6, "Rather than scanning every taxel, each board measures 200 of its 4,096 taxels per frame."),
                     (4.8, 10.8, "Active contacts are tracked, a coarse-to-fine scan monitors the module, and loaded regions are resolved at full density."),
                     (11.3, 16.6, "Recorded acquisition frames: paw contacts are resolved completely, while unloaded regions are sampled sparsely."),
                     (16.8, 21.8, "Adaptive sampling enables acquisition across 16,384 taxels at approximately 1,000 frames per second.")],
    "s06_loading": [(0.3, 6.6, "With synchronized video, contacts are assigned to individual paws, correctly identifying 93.3% of 2,469 manually annotated contacts."),
                    (6.8, 13.7, "The load on each paw is then resolved at approximately 1 kHz throughout every stance.")],
    "s07_injury": [(0.3, 4.4, "After sciatic nerve pinch, rats continued to place the injured hindpaw on the ground."),
                   (4.5, 7.8, "The loading ratio, however, decreased by approximately 60%, nearly twice the decrease in the duty-factor ratio."),
                   (8.3, 11.6, "In three injured and two sham-operated rats followed for two weeks, both ratios decreased and then returned toward baseline."),
                   (11.8, 14.8, "Peak loading of the injured hindpaw decreased by 27%, and that of the contralateral hindpaw increased by 22–23%."),
                   (15.3, 21.7, "Contact morphology also changed: injured-hindpaw contacts became smaller and more elongated (cyan outlines).")],
    "s08_beyond": [(0.3, 4.9, "The modular design allows the same four modules to form other arenas, such as a square open field with three rats."),
                   (5.1, 9.7, "Future applications include integration with pose estimation, neural recordings, contact-triggered perturbations and shear sensing.")],
    "s09_open": [(0.5, 8.6, "Open resources: hardware design files, firmware, analysis software and 85 recordings. tactilearena.github.io")],
}

GAP = 0.5  # dip to black between scenes (s)


def vtt_time(x):
    h = int(x // 3600); m = int(x % 3600 // 60); s = x % 60
    return f"{h:02d}:{m:02d}:{s:06.3f}"


def main():
    still = os.environ.get("STILL")
    if still:
        name, tt = still.split(":")
        for n, dur, fn in SCENES:
            if n.startswith(name):
                os.makedirs(os.path.join(WORK, "shots"), exist_ok=True)
                fn(float(tt)).convert("RGB").save(os.path.join(WORK, "shots", f"ov_{n}_{tt}.jpg"), quality=88)
        return
    out = os.path.join(A, "video", "overview.mp4")
    w = Writer(out, W, H, FPS, crf=21, preset="medium")
    g0 = 0.0; cues = []
    for n, dur, fn in SCENES:
        nf = int(round(dur * FPS))
        for i in range(nf):
            t = i / FPS
            fr = to_arr(fn(t))
            k = min(t, dur - t)
            if k < GAP / 2:
                fr = fr * ease(k / (GAP / 2))
            w.add(fr)
        for a, b, txt in CAPTION_TABLE.get(n, []):
            cues.append((g0 + a, g0 + b, txt))
        g0 += nf / FPS
        print(f"{n}: done ({g0:.1f} s)", flush=True)
    w.close()
    with open(os.path.join(A, "video", "overview.vtt"), "w") as fh:
        fh.write("WEBVTT\n\n")
        for a, b, txt in cues:
            fh.write(f"{vtt_time(a)} --> {vtt_time(b)}\n{txt}\n\n")
    poster(out, out.replace(".mp4", ".jpg"), t=13.5)  # title card
    with open(os.path.join(WORK, "overview_script.md"), "w") as fh:
        fh.write("# TactileArena overview: narration script\n\nTimed to overview.mp4; the on-screen captions carry the same text.\n\n")
        for a, b, txt in cues:
            fh.write(f"- **{vtt_time(a)[3:8]}** {txt}\n")
    print("wrote", out, f"{g0:.1f} s")


if __name__ == "__main__":
    main()
