"""Camera -> sensor-grid registration, reproducing pipeline/s1_prepare_recordings.m (infer_sheet_corners):
rotate the overhead frame 180 deg, map clicked platform corners through the platform template to the
pressure-sheet corners, and fit a projective transform onto the 256 x 64 taxel grid."""
import numpy as np, scipy.io as sio, subprocess, os, warnings
warnings.filterwarnings("ignore", message=".*encountered in matmul")  # spurious on macOS Accelerate numpy
from scipy.ndimage import map_coordinates

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def fit_h(src, dst):
    """Projective transform (3x3) mapping src (N,2) -> dst (N,2), DLT."""
    A = []
    for (x, y), (u, v) in zip(src, dst):
        A.append([-x, -y, -1, 0, 0, 0, u * x, u * y, u])
        A.append([0, 0, 0, -x, -y, -1, v * x, v * y, v])
    _, _, vt = np.linalg.svd(np.asarray(A, float))
    H = vt[-1].reshape(3, 3)
    return H / H[2, 2]


def apply_h(H, pts):
    pts = np.asarray(pts, float)
    p = np.c_[pts, np.ones(len(pts))] @ H.T
    return p[:, :2] / p[:, 2:3]


def sheet_homography(platform_corners):
    """platform_corners: TL, TR, BR, BL in the rot180 camera frame (MATLAB 1-based px).
    Returns H mapping rot180-frame pixel (x, y) [0-based] -> sensor (col, row) in taxels."""
    t = sio.loadmat(os.path.join(REPO, "data", "platform_sheet_template.mat"), squeeze_me=True,
                    struct_as_record=False)["template"]
    pn = np.array([[0, 0], [1, 0], [1, 1], [0, 1]], float)
    P = np.asarray(platform_corners, float) - 1.0  # to 0-based
    n2p = fit_h(pn, P)
    sheet_src = apply_h(n2p, np.asarray(t.sheet_pts_in_platform, float))
    return fit_h(sheet_src, np.asarray(t.dst_pts, float)), sheet_src


def read_frames(path, idx_list, w=1920, h=1080):
    """Read specific frame indices (sorted) from a video via ffmpeg select filter."""
    idx_list = sorted(set(int(i) for i in idx_list))
    sel = "+".join(f"eq(n\\,{i})" for i in idx_list)
    cmd = ["ffmpeg", "-v", "error", "-i", path, "-vf", f"select={sel}", "-fps_mode", "passthrough", "-f", "rawvideo",
           "-pix_fmt", "rgb24", "-"]
    raw = subprocess.run(cmd, capture_output=True, check=True).stdout
    frames = np.frombuffer(raw, np.uint8).reshape(-1, h, w, 3)
    return dict(zip(idx_list, frames))


def read_range(path, start, count, w=1920, h=1080):
    cmd = ["ffmpeg", "-v", "error", "-i", path, "-vf", f"select=between(n\\,{start}\\,{start + count - 1})",
           "-fps_mode", "passthrough", "-f", "rawvideo", "-pix_fmt", "rgb24", "-"]
    raw = subprocess.run(cmd, capture_output=True, check=True).stdout
    return np.frombuffer(raw, np.uint8).reshape(-1, h, w, 3)


class Rectifier:
    """Warp rot180 camera frames into sensor coordinates: output pixel (i, j) <-> taxel
    (col = u0 + j/s, row = v0 + i/s)."""

    def __init__(self, H, s=8, u0=-6, u1=262, v0=-14, v1=78):
        self.Hinv = np.linalg.inv(H)
        self.s = s; self.u0, self.v0 = u0, v0
        self.W = int(round((u1 - u0) * s)); self.Hh = int(round((v1 - v0) * s))
        jj, ii = np.meshgrid(np.arange(self.W), np.arange(self.Hh))
        u = u0 + (jj + 0.5) / s - 0.5; v = v0 + (ii + 0.5) / s - 0.5
        xy = apply_h(self.Hinv, np.c_[u.ravel(), v.ravel()])
        self.cx = xy[:, 0].reshape(self.Hh, self.W); self.cy = xy[:, 1].reshape(self.Hh, self.W)

    def warp(self, frame):
        f = frame[::-1, ::-1]  # rot180
        out = np.empty((self.Hh, self.W, 3), np.uint8)
        for c in range(3):
            out[..., c] = map_coordinates(f[..., c], [self.cy, self.cx], order=1, mode="constant", cval=0)
        return out

    def taxel_to_px(self, col, row):
        return ((np.asarray(col) - self.u0 + 0.5) * self.s, (np.asarray(row) - self.v0 + 0.5) * self.s)
