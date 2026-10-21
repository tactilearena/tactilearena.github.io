"""Supplementary Video 4: adaptive tactile sampling during locomotion (1920x1080, 30 fps, no audio).
  1. title card
  2. one frame of one module, read by read: the firmware's sampling loop run on a simulated paw (labelled)
  3. the recorded packets of all four boards, frame by frame (2026-02-24, rat 4, runway)
  4. the same recording at a faster pace, so the shifting background scan and the moving paws are both visible
Usage: python make_supp_sampling.py out.mp4"""
import os, sys, numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_overview as ov
from make_overview import (W, H, FPS, S, blank, to_img, to_arr, ease, text_block, caption, paint_module, THRESHOLD, EMBER)
from media_common import Writer, poster

T0 = 34.95  # start of the recorded stretch (s on the recording clock)
P0 = [int(np.searchsorted(bd["ts"], T0)) for bd in S.rw.boards]


def title(t):
    im = to_img(blank()).convert("RGBA"); a = ease(t / 0.6)
    text_block(im, (W / 2, 330), ["Supplementary Video 4"], 30, "Medium", fill=EMBER, anchor="ma", alpha=a)
    text_block(im, (W / 2, 390), ["Adaptive tactile sampling during locomotion"], 64, "SemiBold", anchor="ma", alpha=a)
    text_block(im, (W / 2, 500), ["Each readout board reads 200 of its module's 4,096 taxels per frame (M = 200, threshold T = 700).",
                                  "It re-reads last frame's contacts, scans the module coarse-to-fine, and reads the 3 × 3 neighbours",
                                  "of every reading above threshold, until the 200 reads are used."],
               32, "Regular", fill=(210, 204, 220), anchor="ma", alpha=ease((t - 0.6) / 0.6))
    return im


def sim(t):
    """One frame of one module, read by read (simulation of the firmware loop on a simulated paw)."""
    if "frames" not in ov._sm:
        ov._sim_setup()
    im = to_img(blank()).convert("RGBA")
    s = 12; mod_x, mod_y = 150, 50
    truth, log = ov._sm["frames"][40]
    n_show = int(np.clip((t - 0.8) / 8.0, 0, 1) * len(log))
    read = np.zeros((64, 64), bool); val = np.zeros((64, 64)); recent = np.zeros((64, 64), bool)
    for j, (r, c, ph, v) in enumerate(log[:n_show]):
        read[r, c] = True; val[r, c] = v
        if j >= n_show - 3:
            recent[r, c] = True
    ghost = np.where(truth > THRESHOLD, 1.0, 0.0)
    mod = paint_module(val, read, s, recent=recent if n_show < len(log) else None)
    g = np.repeat(np.repeat(ghost, s, 0), s, 1)[..., None]
    mod = np.where((~np.repeat(np.repeat(read, s, 0), s, 1))[..., None] & (g > 0), mod * 0.5 + np.array([60, 30, 70]) * 0.5, mod)
    f = to_arr(im); f[mod_y:mod_y + 64 * s, mod_x:mod_x + 64 * s] = mod; im = to_img(f).convert("RGBA")
    phase = log[n_show - 1][2] if n_show else "follow"
    counts = {p: sum(1 for x in log[:n_show] if x[2] == p) for p in ("follow", "scan", "zoom")}
    tx = mod_x + 64 * s + 90
    text_block(im, (tx, mod_y), ["Single acquisition frame of one module"], 44, "SemiBold")
    text_block(im, (tx, mod_y + 60), ["Simulation of the firmware sampling loop on a simulated paw"], 26, fill=(170, 162, 182))
    text_block(im, (tx, mod_y + 110), [f"taxels measured: {n_show:3d} / 200 of 4,096"], 34, "Regular", fill=EMBER)
    rows = [("follow", "1  Tracking of previous contacts"), ("scan", "2  Coarse-to-fine background scan"),
            ("zoom", "3  Neighbourhood expansion above threshold")]
    y = mod_y + 200
    for key, label in rows:
        on = (key == phase and n_show < len(log))
        text_block(im, (tx, y), [label], 34, "Medium" if on else "Regular", fill=(255, 255, 255) if on else (150, 142, 162))
        text_block(im, (tx + 40, y + 46), [f"{counts[key]} measurement" + ("" if counts[key] == 1 else "s")], 26, fill=(150, 142, 162))
        y += 120
    text_block(im, (tx, y + 10), ["Purple shading: applied pressure not yet measured.", "White: most recent measurements."], 24,
               fill=(150, 142, 162))
    caption(im, t, [(0.3, 5.8, "During locomotion only a small fraction of the floor is loaded, so most measurements in each frame are allocated to active contacts."),
                    (6.0, 11.7, "After 200 measurements the frame is transmitted; the next frame begins with the taxels that triggered expansion in this frame.")], 0)
    return im


def boards(i, label, legend_alpha=1.0):
    im = to_img(blank()).convert("RGBA")
    s2 = 7; top = 170; x0 = (W - 256 * s2) // 2; f = to_arr(im); tot = 0
    for k, bd in enumerate(S.rw.boards):
        p = P0[k] + i; a_, b_ = bd["off"][p], bd["off"][p + 1]
        val = np.zeros(4096); rd = np.zeros(4096, bool)
        val[bd["rc"][a_:b_]] = bd["val"][a_:b_]; rd[bd["rc"][a_:b_]] = True; tot += b_ - a_
        f[top:top + 64 * s2, x0 + 64 * s2 * k:x0 + 64 * s2 * (k + 1)] = paint_module(val.reshape(64, 64), rd.reshape(64, 64), s2)
    im = to_img(f).convert("RGBA")
    tnow = S.rw.boards[0]["ts"][P0[0] + i]
    text_block(im, (x0, top - 72), [label], 32, "Medium")
    text_block(im, (x0 + 256 * s2, top - 72), [f"t = {tnow:.3f} s    measured in this frame: {tot} of 16,384 taxels"], 30,
               fill=EMBER, anchor="ra")
    for k in range(4):
        text_block(im, (x0 + 64 * s2 * k + 8, top + 64 * s2 + 10), [f"board {4 - k}"], 22, fill=(130, 122, 142))
    text_block(im, (x0, top + 64 * s2 + 52), ["black: not measured in this frame     grey: measured, below threshold     colour: measured, above threshold"],
               26, fill=(170, 162, 182), alpha=legend_alpha)
    return im


def real_slow(t):
    i = int(t * 12)  # 12 board frames per second of video (~1/80 of real time)
    im = boards(i, "Recorded acquisition frames (24 February 2026, rat 4, runway)")
    caption(im, t, [(0.3, 6.6, "In each recorded frame, the 200 measurements of each board are distributed between the paw contacts and a sparse background grid."),
                    (6.8, 13.7, "Modules without active contacts allocate their full budget to the background scan, which therefore reaches a finer grid."),
                    (13.9, 19.7, "The background grid shifts by one column each frame, so that every taxel is measured over successive frames.")], 0)
    return im


def real_fast(t):
    i = 240 + int(t * 120)  # 120 board frames per second of video (~1/8 of real time)
    im = boards(i, "Same recording at approximately 1/8 of real time")
    caption(im, t, [(0.3, 9.7, "Each contact remains fully resolved from touchdown to lift-off, while unloaded regions are sampled sparsely.")], 0)
    return im


SEGMENTS = [(title, 4.0), (sim, 12.0), (real_slow, 20.0), (real_fast, 10.0)]


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
    poster(out, out.replace(".mp4", ".jpg"), t=24.0)
    print("wrote", out)


if __name__ == "__main__":
    if os.environ.get("STILL"):
        name, tt = os.environ["STILL"].split(":")
        fn = dict((f.__name__, f) for f, _ in SEGMENTS)[name]
        fn(float(tt)).convert("RGB").save(os.path.join(ov.WORK, "shots", f"s4_{name}_{tt}.jpg"), quality=88)
    else:
        main(sys.argv[1])
