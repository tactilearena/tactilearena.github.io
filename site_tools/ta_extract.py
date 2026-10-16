"""Convert a TactileArena runway .mat (per-board sparse packets) into a compact CSR cache (npz)."""
import sys, time, numpy as np, scipy.io as sio
src, dst = sys.argv[1], sys.argv[2]
t0 = time.time()
d = sio.loadmat(src, squeeze_me=True)
print("loaded in %.1fs" % (time.time() - t0), flush=True)
out = {}
for k in ["M", "threshold", "digipot", "duration", "shared_start_time"]:
    out[k] = np.asarray(d[k])
for b in [1, 2, 3, 4]:
    ts = np.asarray(d[f"Board{b}_timestamps"], float)
    idx = d[f"Board{b}_pixel_indices"]; val = d[f"Board{b}_pixel_values"]
    cnt = np.array([np.size(x) for x in idx], np.int32)
    off = np.concatenate([[0], np.cumsum(cnt)]).astype(np.int64)
    fi = np.concatenate([np.atleast_1d(x).astype(np.uint16) for x in idx])
    fv = np.concatenate([np.atleast_1d(x).astype(np.uint16) for x in val])
    out[f"b{b}_ts"], out[f"b{b}_off"], out[f"b{b}_idx"], out[f"b{b}_val"] = ts, off, fi, fv
    out[f"b{b}_ids"] = np.asarray(d[f"Board{b}_board_ids"])
    print(f"Board{b}: frames={len(ts)} span={ts[0]:.3f}..{ts[-1]:.3f}s rate={len(ts)/(ts[-1]-ts[0]):.1f}/s "
          f"taxels/frame median={np.median(cnt):.0f} min={cnt.min()} max={cnt.max()} board_id={np.unique(out[f'b{b}_ids'])} "
          f"overflows={d[f'Board{b}_buffer_overflows']}", flush=True)
for c in [0, 1]:
    out[f"cam{c}_ts"] = np.asarray(d[f"camera{c}_frame_timestamps"], float)
    out[f"cam{c}_fi"] = np.asarray(d[f"camera{c}_frame_indices"])
    print(f"camera{c}: frames={len(out[f'cam{c}_ts'])} fps={d[f'camera{c}_actual_fps']} dropped={d[f'camera{c}_dropped_frames']} "
          f"ts {out[f'cam{c}_ts'][0]:.3f}..{out[f'cam{c}_ts'][-1]:.3f}", flush=True)
np.savez(dst, **out)
print("saved", dst, "%.1fs" % (time.time() - t0))
