"""Collect and convert the website's static assets into docs/assets/.
Sources (outside the repo; paths are Ariel's OneDrive):
  photos   figure-design deck (testing_rat/figure_designs_correct.pptx) media
  figures  manuscript figure PDFs (Gait_Project_Paper/overleaf/figures), cropped like main 4.0.tex does
  videos   Victor's build guide and annotated recordings (testing_rat/!Videos), demo clips
Re-run after any source changes: python site_tools/make_site_assets.py [photos|figures|videos]"""
import os, sys, subprocess, zipfile, io
from PIL import Image

HOME = os.path.expanduser("~")
ONE_JHU = os.path.join(HOME, "Library/CloudStorage/OneDrive-JohnsHopkins")
ONE_MIT = os.path.join(HOME, "Library/CloudStorage/OneDrive-MassachusettsInstituteofTechnology")
TESTING = os.path.join(ONE_JHU, "testing_rat")
PAPER = os.path.join(ONE_MIT, "Gait_Project_Paper", "overleaf", "figures")
REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
A = os.path.join(REPO, "docs", "assets")
WORK = os.path.join(REPO, ".work")


def save_jpg(im, path, width=None, q=86):
    im = im.convert("RGB")
    if width and im.width > width:
        im = im.resize((width, round(im.height * width / im.width)), Image.LANCZOS)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    im.save(path, quality=q, optimize=True, progressive=True)
    print("  ", os.path.relpath(path, REPO), im.size)


def save_png(im, path, width=None):
    if width and im.width > width:
        im = im.resize((width, round(im.height * width / im.width)), Image.LANCZOS)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    im.save(path, optimize=True)
    print("  ", os.path.relpath(path, REPO), im.size)


def photos():
    z = zipfile.ZipFile(os.path.join(TESTING, "figure_designs_correct.pptx"))
    get = lambda n: Image.open(io.BytesIO(z.read("ppt/media/" + n)))
    save_jpg(get("image53.png"), f"{A}/photos/runway_rat.jpg", 1400)        # runway with rat + live map inset
    save_jpg(get("image50.jpeg"), f"{A}/photos/runway_rat_raw.jpg", 1600)   # rat on the runway (raw photo)
    save_png(get("image55.png"), f"{A}/photos/module.png", 1400)            # one 64x64 sensor + readout board
    save_png(get("image56.png"), f"{A}/photos/modules_2x2.png", 1400)       # four modules tiled 2x2
    save_jpg(get("image179.jpeg"), f"{A}/photos/readout_board.jpg", 1400)   # readout board with Teensy 4.1
    save_jpg(get("image180.jpeg"), f"{A}/photos/sensor_array.jpg", 1400)    # bare 64x64 flex sensor


# (file, page, trim in bp: left, bottom, right, top) as in main 4.0.tex, plus output name
FIGS = [
    ("Figure 1.pdf", 1, (8, 345, 90, 98), "fig1_workflow"),
    ("overview.pdf", 1, (20, 120, 20, 70), "overview"),
    ("sensor.pdf", 1, (0, 0, 0, 0), "fig3_contacts"),
    ("trajectory.pdf", 1, (3, 10, 700, 20), "fig2_cop"),
    ("frequency sweep.pdf", 1, (0, 57, 0, 31), "fig4_sampling"),
    ("analysis.pdf", 1, (0, 40, 0, 10), "fig5_sni"),
    ("sensor characterization.pdf", 1, (15, 100, 10, 15), "figS1_characterization"),
    ("algorithm.pdf", 1, (0, 0, 0, 0), "figS2_decoder"),
    ("cop analysis.pdf", 1, (0, 0, 5, 0), "figS3_within_paw_cop"),
]


def figures(dpi=220):
    tmp = os.path.join(WORK, "figtmp"); os.makedirs(tmp, exist_ok=True)
    for fn, page, (l, b, r, t), name in FIGS:
        src = os.path.join(PAPER, fn)
        base = os.path.join(tmp, name)
        subprocess.run(["pdftoppm", "-r", str(dpi), "-f", str(page), "-l", str(page), "-png", "-singlefile", src, base],
                       check=True)
        im = Image.open(base + ".png")
        k = dpi / 72
        im = im.crop((round(l * k), round(t * k), im.width - round(r * k), im.height - round(b * k)))
        # trim uniform white margins
        bg = Image.new(im.mode, im.size, (255, 255, 255) if im.mode == "RGB" else 255)
        from PIL import ImageChops
        bbox = ImageChops.difference(im.convert("RGB"), bg.convert("RGB")).getbbox()
        if bbox:
            pad = 12
            im = im.crop((max(bbox[0] - pad, 0), max(bbox[1] - pad, 0), min(bbox[2] + pad, im.width), min(bbox[3] + pad, im.height)))
        save_jpg(im, f"{A}/figures/{name}.jpg", 2000, q=90)


def ff(args):
    subprocess.run(["ffmpeg", "-v", "error", "-y", *args], check=True)


def videos():
    V = os.path.join(TESTING, "!Videos")
    D = os.path.join(TESTING, "11-03-2025", "Videos", "Demo Videos")
    out = f"{A}/video"; os.makedirs(out, exist_ok=True)
    # build guide: vertical phone video with burned-in captions, keep it legible
    ff(["-i", f"{V}/assembly.MP4", "-vf", "scale=720:-2", "-c:v", "libx264", "-preset", "slow", "-crf", "27",
        "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "96k", "-movflags", "+faststart", f"{out}/assembly.mp4"])
    ff(["-ss", "20", "-i", f"{out}/assembly.mp4", "-frames:v", "1", "-q:v", "4", f"{out}/assembly.jpg"])
    for n in ("pre-surgery", "post-surgery"):
        ff(["-i", f"{V}/{n}.MP4", "-vf", "scale=1280:-2", "-c:v", "libx264", "-preset", "slow", "-crf", "25",
            "-pix_fmt", "yuv420p", "-an", "-movflags", "+faststart", f"{out}/{n}.mp4"])
        ff(["-ss", "4", "-i", f"{out}/{n}.mp4", "-frames:v", "1", "-q:v", "4", f"{out}/{n}.jpg"])
    # open-arena demonstration (not analysed in the paper): three rats on four modules tiled 2x2
    ff(["-ss", "8", "-t", "24", "-i", f"{D}/multi animal.mov", "-vf", "fps=30,scale=1600:-2", "-c:v", "libx264",
        "-preset", "slow", "-crf", "25", "-pix_fmt", "yuv420p", "-an", "-movflags", "+faststart", f"{out}/arena_multi.mp4"])
    ff(["-ss", "10", "-i", f"{out}/arena_multi.mp4", "-frames:v", "1", "-q:v", "4", f"{out}/arena_multi.jpg"])
    ff(["-ss", "6", "-t", "16", "-i", f"{D}/benchtop test.mp4", "-vf", "fps=30,scale=1280:-2", "-c:v", "libx264",
        "-preset", "slow", "-crf", "26", "-pix_fmt", "yuv420p", "-an", "-movflags", "+faststart", f"{out}/arena_bench.mp4"])
    ff(["-ss", "4", "-i", f"{out}/arena_bench.mp4", "-frames:v", "1", "-q:v", "4", f"{out}/arena_bench.jpg"])
    for f in sorted(os.listdir(out)):
        print("  ", f, os.path.getsize(os.path.join(out, f)) // 1024, "KB")


if __name__ == "__main__":
    which = sys.argv[1:] or ["photos", "figures", "videos"]
    for w in which:
        print(w); globals()[w]()
