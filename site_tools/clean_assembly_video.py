"""Supplementary Video 1 (assembly): replace the burned-in step captions with formal captions.

The source recording carries its own on-screen captions. Each is covered, for its full duration, by a caption box in
the style of the other videos, stating the same step in formal terms. Caption times and extents were measured
frame by frame from the source (blue-outlined caption text, constant within each caption). The audio track
(background music) is dropped.

  python site_tools/clean_assembly_video.py

Reads assembly.mp4 (1080 x 1920) from TA_SOURCES. Writes the full-quality Supplementary Video 1 to
<TA_WORK>/supplementary and the website copy (docs/assets/video/assembly.mp4/.jpg).
"""
import os, sys, subprocess
import numpy as np
from PIL import Image, ImageDraw
from media_common import REPO, WORK, SOURCES, font

W, H, FPS = 1080, 1920, 30
# (start s, end s, x0, y0, x1, y1) of each source caption, and the formal caption shown in its place
CAPTIONS = [
    ((0.637, 1.237, 102, 1149, 969, 1227), ["Readout board with Teensy 4.1 microcontroller"]),
    ((2.033, 2.467, 126, 1502, 943, 1613), ["Flexible 64 × 64 sensor array"]),
    ((3.433, 6.433, 58, 1438, 1004, 1583), ["Insertion of the sensor tails", "into the readout-board connectors"]),
    ((21.763, 24.763, 134, 1180, 961, 1233), ["Alignment of the four sensor arrays"]),
    ((51.737, 52.637, 292, 1182, 773, 1291), ["Piezoresistive film"]),
    ((53.397, 56.397, 110, 1142, 953, 1193), ["Application of the film over the four arrays"]),
    ((74.797, 77.797, 128, 1132, 967, 1187), ["Connection of the readout boards to the host computer"]),
    ((91.967, 93.400, 20, 1132, 1065, 1281), ["Verification with the live viewer:", "the indicator LED of each readout board is lit"]),
]
MIN_SHOW = 2.0      # s; brief source labels are kept on screen at least this long (until the next caption)
PAD = 3 / FPS       # s; margin before and after each source caption
SIZE, LINE = 40, 54  # px


def overlay(box, lines):
    """RGBA caption box covering the source caption's extent (widened if the text needs it)."""
    x0, y0, x1, y1 = box
    f = font(SIZE, "SemiBold")
    tw = max(ImageDraw.Draw(Image.new("L", (1, 1))).textlength(t, font=f) for t in lines)
    w = min(W - 24, max(x1 - x0 + 36, tw + 56)); h = max(y1 - y0 + 30, len(lines) * LINE + 28)
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    bx0 = int(max(12, min(W - 12 - w, cx - w / 2))); by0 = int(cy - h / 2)
    im = Image.new("RGBA", (int(w), int(h)), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rounded_rectangle((0, 0, w - 1, h - 1), radius=14, fill=(12, 14, 20, 255))
    for i, t in enumerate(lines):
        d.text((w / 2, h / 2 + (i - (len(lines) - 1) / 2) * LINE), t, font=f, fill=(255, 255, 255, 255), anchor="mm")
    return bx0, by0, np.asarray(im).astype(np.float32)


def main(src, out_dir):
    os.makedirs(out_dir, exist_ok=True)
    web = os.path.join(REPO, "docs", "assets", "video")
    shows = []
    for i, ((a, b, *box), lines) in enumerate(CAPTIONS):
        nxt = CAPTIONS[i + 1][0][0] - PAD if i + 1 < len(CAPTIONS) else 1e9
        shows.append((a - PAD, min(max(b + PAD, a + MIN_SHOW), nxt), *overlay(box, lines)))
    dec = subprocess.Popen(["ffmpeg", "-v", "error", "-i", src, "-f", "rawvideo", "-pix_fmt", "rgb24", "-"],
                           stdout=subprocess.PIPE)
    full = os.path.join(out_dir, "SupplementaryVideo1_assembly.mp4")
    enc = subprocess.Popen(
        ["ffmpeg", "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{W}x{H}", "-r", str(FPS),
         "-i", "-", "-filter_complex", "[0]split=2[a][b];[b]scale=720:-2[c]",
         "-map", "[a]", "-c:v", "libx264", "-preset", "slow", "-crf", "20", "-pix_fmt", "yuv420p",
         "-movflags", "+faststart", full,
         "-map", "[c]", "-c:v", "libx264", "-preset", "slow", "-crf", "27", "-pix_fmt", "yuv420p",
         "-movflags", "+faststart", os.path.join(web, "assembly.mp4")], stdin=subprocess.PIPE)
    n = 0
    while True:
        b = dec.stdout.read(W * H * 3)
        if len(b) < W * H * 3:
            break
        fr = np.frombuffer(b, np.uint8).reshape(H, W, 3).copy()
        t = n / FPS
        for t0, t1, bx, by, ov in shows:
            if t0 <= t < t1:
                h, w = ov.shape[:2]
                reg = fr[by:by + h, bx:bx + w].astype(np.float32)
                a = ov[..., 3:4] / 255
                fr[by:by + h, bx:bx + w] = (reg * (1 - a) + ov[..., :3] * a).astype(np.uint8)
        enc.stdin.write(fr.tobytes()); n += 1
    enc.stdin.close(); enc.wait(); dec.wait()
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-ss", "20", "-i", os.path.join(web, "assembly.mp4"),
                    "-frames:v", "1", "-q:v", "4", os.path.join(web, "assembly.jpg")], check=True)
    print(f"  {n} frames -> {full}")


if __name__ == "__main__":
    main(os.path.join(SOURCES, "assembly.mp4"), os.path.join(WORK, "supplementary"))
