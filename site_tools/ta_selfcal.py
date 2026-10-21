"""Camera-to-sensor registration without a saved homography.
Start from the pipeline's platform template (data/platform_sheet_template.mat: pressure-sheet corners in the
rot180 overhead frame of the template session) and search for the similarity correction (in sensor space)
that puts the most pressure inside the rat's video silhouette: paws are always under the body outline.
Usage: ta_selfcal.py cache.npz camera.mp4 out.json [camera_index]"""
import sys, os, json, numpy as np, subprocess, scipy.io as sio
from scipy import ndimage as ndi
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ta_frames import Runway
from ta_register import fit_h, apply_h, REPO

cache, video, out_json = sys.argv[1], sys.argv[2], sys.argv[3]
cam = int(sys.argv[4]) if len(sys.argv) > 4 else 1
rw = Runway(cache)
cts = rw.cam_ts[cam]
tpl = sio.loadmat(os.path.join(REPO, "data", "platform_sheet_template.mat"), squeeze_me=True,
                  struct_as_record=False)["template"]
dst_pts = np.asarray(tpl.dst_pts, float)
H0 = fit_h(np.asarray(tpl.sheet_src_pts, float) - 1, dst_pts)

W, H, S = 960, 540, 2
raw = subprocess.run(["ffmpeg", "-v", "error", "-i", video, "-vf", f"scale={W}:{H}", "-f", "rawvideo",
                      "-pix_fmt", "gray", "-"], capture_output=True, check=True).stdout
V = np.frombuffer(raw, np.uint8).reshape(-1, H, W)[:, ::-1, ::-1]  # rot180
n = min(len(V), len(cts))
bg = np.median(V[np.linspace(0, n - 1, 80).astype(int)], axis=0)
st = ndi.generate_binary_structure(2, 1)
masks, pts = [], []
for i in range(0, n, 2):
    if cts[i] > rw.t_end:
        break
    m = (V[i].astype(np.int16) - bg) > 45
    m = ndi.binary_opening(m, structure=st, iterations=4)
    lab, k = ndi.label(m)
    if k == 0:
        continue
    sizes = ndi.sum(m, lab, range(1, k + 1)); j = int(np.argmax(sizes)) + 1
    if sizes[j - 1] < 1500:
        continue
    body = ndi.binary_dilation(lab == j, iterations=3)
    P = rw.frame(cts[i]); r, c = np.nonzero(P > 700)
    if len(r) < 15:
        continue
    masks.append(body); pts.append(np.c_[c, r, P[r, c]])
print("frames used", len(masks))
fid = np.concatenate([np.full(len(p), k) for k, p in enumerate(pts)])
allp = np.concatenate(pts).astype(float)
masks = np.stack(masks)


def score(C):
    Hc = C @ H0
    xy = apply_h(np.linalg.inv(Hc), allp[:, :2]) / S  # camera half-res px
    x = np.round(xy[:, 0]).astype(int); y = np.round(xy[:, 1]).astype(int)
    ok = (x >= 0) & (x < W) & (y >= 0) & (y < H)
    inside = np.zeros(len(x), bool)
    inside[ok] = masks[fid[ok], y[ok], x[ok]]
    return (allp[:, 2] * inside).sum() / allp[:, 2].sum()


def sim(s, th, tx, ty, cx=128, cy=32):  # scale/rotate about the sheet centre, then shift (taxels)
    c, sn = s * np.cos(th), s * np.sin(th)
    return np.array([[c, -sn, cx - c * cx + sn * cy + tx], [sn, c, cy - sn * cx - c * cy + ty], [0, 0, 1.0]])


print("template only: %.3f of pressure inside body" % score(np.eye(3)))
best = (score(np.eye(3)), 1, 0, 0, 0)
for tx in range(-24, 25, 2):
    for ty in range(-24, 25, 2):
        v = score(sim(1, 0, tx, ty))
        if v > best[0]:
            best = (v, 1, 0, tx, ty)
print("coarse", best)
for step_t, step_s, step_r in [(1, 0.02, 0.01), (0.5, 0.01, 0.005), (0.25, 0.005, 0.0025)]:
    improved = True
    while improved:
        improved = False
        _, s0, r0, x0, y0 = best
        for s in (s0 - step_s, s0, s0 + step_s):
            for r in (r0 - step_r, r0, r0 + step_r):
                for x in (x0 - step_t, x0, x0 + step_t):
                    for y in (y0 - step_t, y0, y0 + step_t):
                        v = score(sim(s, r, x, y))
                        if v > best[0] + 1e-6:
                            best = (v, s, r, x, y); improved = True
print("refined: inside=%.3f scale=%.3f rot=%.2f deg shift=(%.2f, %.2f) taxels" % (best[0], best[1], np.degrees(best[2]), best[3], best[4]))
Hc = sim(*best[1:]) @ H0
corners = apply_h(np.linalg.inv(Hc), dst_pts)
json.dump({"H_rot180px_to_taxel": (Hc / Hc[2, 2]).tolist(), "sheet_corners_rot180px": corners.tolist(),
           "pressure_inside_body": best[0], "frames": int(len(masks)),
           "method": "platform template + similarity correction maximising pressure inside the body silhouette"},
          open(out_json, "w"), indent=1)
print("sheet corners (rot180 px):", np.round(corners, 1))
