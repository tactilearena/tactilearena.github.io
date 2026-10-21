"""Collect and convert the website's static assets into docs/assets/.

Sources (TA_SOURCES, see site_tools/README.md):
  photos   figure_deck.pptx and poster_ner2025.pptx (embedded photographs)
  figures  manuscript figure PDFs in TA_PAPER_FIGS (default: <TA_SOURCES>/manuscript_figures), trimmed as in the
           manuscript source
  videos   arena_three_rats.mov (three rats on the 2 x 2 arena)
Supplementary Videos 1-3 and their website copies are produced by clean_assembly_video.py and
clean_annotated_videos.py; Videos 4 and 5 by make_supp_sampling.py and make_supp_square.py.

  python site_tools/make_site_assets.py [photos|figures|cards|videos]
"""
import os, sys, subprocess, zipfile, io
from PIL import Image

from media_common import REPO, WORK, SOURCES

PAPER = os.environ.get("TA_PAPER_FIGS", os.path.join(SOURCES, "manuscript_figures"))
A = os.path.join(REPO, "docs", "assets")


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
    z = zipfile.ZipFile(os.path.join(SOURCES, "figure_deck.pptx"))
    get = lambda n: Image.open(io.BytesIO(z.read("ppt/media/" + n)))
    save_png(get("image55.png"), f"{A}/photos/module.png", 1400)            # one 64x64 sensor + readout board
    save_png(get("image56.png"), f"{A}/photos/modules_2x2.png", 1400)       # four modules tiled 2x2
    # The 64x64 readout board, cropped from the module photo (same image as the manuscript's overview figure).
    # Note: the deck's other close-ups (image179/image180) are the 32x32 design, not this project's hardware.
    mod = get("image55.png").convert("RGBA")
    bg = Image.new("RGBA", mod.size, (11, 8, 16, 255)); mod = Image.alpha_composite(bg, mod)
    save_jpg(mod.crop((90, 460, 760, 1290)), f"{A}/photos/readout_64x64.jpg", 1000)
    # The assembled runway: four modules under the cloth, four readout boards along one side.
    zp = zipfile.ZipFile(os.path.join(SOURCES, "poster_ner2025.pptx"))
    save_jpg(Image.open(io.BytesIO(zp.read("ppt/media/image10.png"))), f"{A}/photos/runway_assembled.jpg", 1200)


# (file, page, trim in bp: left, bottom, right, top) as in the manuscript source, plus output name
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
        if not os.path.exists(src):
            print("   skip (not in source):", fn); continue
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


# Home-page card images: crops of the manuscript figures produced by figures() (pixel boxes in those JPEGs).
CARDS = [
    ("fig2_cop", (8, 1098, 985, 1998), "card_cop"),            # Fig. 3d, presurgical walking sequences
    ("fig1_workflow", (812, 656, 1213, 1056), "card_fusion"),  # Fig. 1D, camera-assisted paw assignment
]


def cards():
    for src, box, name in CARDS:
        save_jpg(Image.open(f"{A}/figures/{src}.jpg").crop(box), f"{A}/figures/{name}.jpg", 1200, q=90)


# The three-rat arena clip is a screen recording with its own panel titles above the tactile map and the overhead
# camera; the frame is cropped below them (1920 x 904 from row 156) and the panels are labelled where it is shown.
MULTI_CROP = "crop=1920:904:0:156"


def videos():
    out = f"{A}/video"; os.makedirs(out, exist_ok=True)
    # open-field arena: three rats on four modules tiled 2 x 2
    ff(["-ss", "8", "-t", "24", "-i", os.path.join(SOURCES, "arena_three_rats.mov"), "-vf",
        f"fps=30,{MULTI_CROP},scale=1600:-2", "-c:v", "libx264", "-preset", "slow", "-crf", "25", "-pix_fmt", "yuv420p",
        "-an", "-movflags", "+faststart", f"{out}/arena_multi.mp4"])
    ff(["-ss", "10", "-i", f"{out}/arena_multi.mp4", "-frames:v", "1", "-q:v", "4", f"{out}/arena_multi.jpg"])
    for f in sorted(os.listdir(out)):
        print("  ", f, os.path.getsize(os.path.join(out, f)) // 1024, "KB")


if __name__ == "__main__":
    which = sys.argv[1:] or ["photos", "figures", "cards", "videos"]
    for w in which:
        print(w); globals()[w]()
