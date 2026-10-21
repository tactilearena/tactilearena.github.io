"""Supplementary Videos 2 and 3: formal title line and removal of a diagnostic annotation.

The annotated recordings are rendered by the analysis pipeline (s4_label_paws with video output). This script
replaces the pipeline's title line (recording file name) with a descriptive title and removes the annotation
"(label row N)" from the four paw panels, leaving "stance N%" / "swing". Nothing else is changed.

  python site_tools/clean_annotated_videos.py

Reads annotated_pre_surgery.mp4 and annotated_post_surgery.mp4 (1280 x 1000) from TA_SOURCES. Writes the
full-quality Supplementary Video files to <TA_WORK>/supplementary and the website copies
(docs/assets/video/{pre,post}-surgery.mp4/.jpg).
"""
import os, sys, subprocess
import numpy as np
from PIL import Image, ImageDraw
from media_common import REPO, WORK, SOURCES, font

W, H = 1280, 1000
VIDEOS = {
    "pre-surgery": ("SupplementaryVideo2_walking_before_surgery.mp4",
                    [("Before sciatic nerve pinch", "SemiBold"),
                     ("   ·   Rat 6, 11 February 2026   ·   Labelled paw contacts and the plantar "
                      "pressure of each paw   ·   0.25× real time", "Regular")]),
    "post-surgery": ("SupplementaryVideo3_walking_after_surgery.mp4",
                     [("Nine days after left sciatic nerve pinch", "SemiBold"),
                      ("   ·   Rat 4, 19 March 2026   ·   Labelled paw contacts and the plantar "
                       "pressure of each paw   ·   0.25× real time", "Regular")]),
}
# text line at the top left of each paw panel: (y0, y1, x0, x1)
BANDS = [(464, 492, 60, 250), (464, 492, 686, 876), (759, 787, 60, 250), (759, 787, 686, 876)]


def frames(path):
    p = subprocess.Popen(["ffmpeg", "-v", "error", "-i", path, "-f", "rawvideo", "-pix_fmt", "rgb24", "-"],
                         stdout=subprocess.PIPE)
    while True:
        b = p.stdout.read(W * H * 3)
        if len(b) < W * H * 3:
            break
        yield np.frombuffer(b, np.uint8).reshape(H, W, 3).copy()
    p.wait()


def text_columns(fr, k, bg, plain):
    """Columns of band k that contain annotation text (darker than the text-free background)."""
    y0, y1, x0, x1 = BANDS[k]
    d = bg[k].mean(-1) - fr[y0:y1, x0:x1].mean(-1)
    return ((d > 45) & plain[k]).any(0)


def title_strip(parts):
    """White strip with the title, drawn over the pipeline's title line."""
    im = Image.new("RGB", (W, 44), (255, 255, 255))
    d = ImageDraw.Draw(im)
    x = 32
    for text, weight in parts:
        f = font(17, weight)
        d.text((x, 22), text, font=f, fill=(20, 20, 20), anchor="lm")
        x += d.textlength(text, font=f)
    return np.asarray(im)


def clean(src, dst_full, dst_web, parts):
    # pass 1: text-free background of each annotation band (per-pixel maximum over frames; text is darker)
    bg = [None] * len(BANDS)
    for fr in frames(src):
        for k, (y0, y1, x0, x1) in enumerate(BANDS):
            b = fr[y0:y1, x0:x1]
            bg[k] = b.copy() if bg[k] is None else np.maximum(bg[k], b)
    # Text is detected only where the background is plain (axis and grid lines carry compression noise).
    plain = [b.mean(-1) > 225 for b in bg]
    strip = title_strip(parts)
    enc = subprocess.Popen(
        ["ffmpeg", "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{W}x{H}", "-r", "30",
         "-i", "-", "-filter_complex", "[0]split=2[a][b]",
         "-map", "[a]", "-c:v", "libx264", "-preset", "slow", "-crf", "17", "-pix_fmt", "yuv420p",
         "-movflags", "+faststart", dst_full,
         "-map", "[b]", "-c:v", "libx264", "-preset", "slow", "-crf", "25", "-pix_fmt", "yuv420p",
         "-movflags", "+faststart", dst_web], stdin=subprocess.PIPE)
    n = removed = 0
    for fr in frames(src):
        fr[:44] = strip
        for k, (y0, y1, x0, x1) in enumerate(BANDS):
            cols = text_columns(fr, k, bg, plain)
            # "stance N%" ends before column 77 (the percentage is right-aligned); the annotation follows after a
            # gap of at least three blank columns
            g = next(c for c in range(70, len(cols)) if not cols[c:c + 3].any())
            if cols[g:].any():
                # restore the uncoloured pixels of the annotation's extent (text and its compression halo); coloured
                # pixels, i.e. a pressure surface reaching into the band, are kept
                e = min(x1 - x0, g + 100)
                f = fr[y0:y1, x0 + g:x0 + e].astype(int)
                grey = (f.max(-1) - f.min(-1)) < 40
                fr[y0:y1, x0 + g:x0 + e][grey] = bg[k][:, g:e][grey]
                removed += 1
        enc.stdin.write(fr.tobytes()); n += 1
    enc.stdin.close(); enc.wait()
    print(f"  {os.path.basename(src)}: {n} frames, annotation removed in {removed} panel-frames")


if __name__ == "__main__":
    out_dir = os.path.join(WORK, "supplementary")
    web = os.path.join(REPO, "docs", "assets", "video")
    os.makedirs(out_dir, exist_ok=True)
    for name, (full_name, parts) in VIDEOS.items():
        clean(os.path.join(SOURCES, f"annotated_{name.replace('-', '_')}.mp4"), os.path.join(out_dir, full_name),
              os.path.join(web, f"{name}.mp4"), parts)
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-ss", "4", "-i", os.path.join(web, f"{name}.mp4"),
                        "-frames:v", "1", "-q:v", "4", os.path.join(web, f"{name}.jpg")], check=True)
