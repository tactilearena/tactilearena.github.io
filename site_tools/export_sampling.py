"""Export data for the website's sampling explainers:
  docs/assets/data/scan_order.json  the firmware's coarse-to-fine background order (ctrMsrRows/ctrMsrCols)
  docs/assets/data/replay.bin/.json a short stretch of a real recording, packet by packet: for every frame of
                                    every board, which taxels it read and what it got.
Binary layout per board (little endian, each section padded to 4 bytes):
  ts float32[n] (s, relative to t0) | count uint16[n] | idx uint16[sum] (row*64+col in the module) |
  val uint8[sum] (raw value / 16, clipped to 255)"""
import os, sys, re, json, glob, numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ta_frames import Runway
from media_common import WORK, REPO, THRESHOLD

out_dir = os.path.join(REPO, "docs", "assets", "data")
os.makedirs(out_dir, exist_ok=True)
src = open(glob.glob(os.path.join(REPO, "acquisition", "firmware", "*", "*.ino"))[0]).read()
rows = [int(x) for x in re.search(r"int ctrMsrRows\[N\] = \{([^}]*)\}", src).group(1).split(",")]
cols = [int(x) for x in re.search(r"int ctrMsrCols\[N\] = \{([^}]*)\}", src).group(1).split(",")]
json.dump({"rows": rows, "cols": cols}, open(os.path.join(out_dir, "scan_order.json"), "w"), separators=(",", ":"))

t0, t1 = (float(sys.argv[1]), float(sys.argv[2])) if len(sys.argv) > 2 else (34.85, 35.45)
rw = Runway(os.path.join(WORK, "cache", "rat4_0224.npz"))
blob = bytearray(); meta = {"t0": t0, "t1": t1, "recording": "2026-02-24, rat 4 (nerve-pinch group, two weeks before surgery), runway",
                           "M": rw.M, "threshold": THRESHOLD, "value_scale": 16, "boards": []}


def pad():
    while len(blob) % 4:
        blob.append(0)


for k, bd in enumerate(rw.boards):
    ts = bd["ts"]
    p0 = max(int(np.searchsorted(ts, t0)) - 1, 0); p1 = int(np.searchsorted(ts, t1))
    off = bd["off"]
    cnt = np.diff(off[p0:p1 + 1]).astype(np.uint16)
    idx = bd["rc"][off[p0]:off[p1]].astype(np.uint16)
    val = np.clip(np.round(bd["val"][off[p0]:off[p1]] / 16.0), 0, 255).astype(np.uint8)
    b = {"hid": bd["hid"], "n": int(p1 - p0), "taxels": int(cnt.sum())}
    b["ts"] = len(blob); blob += (ts[p0:p1] - t0).astype(np.float32).tobytes(); pad()
    b["count"] = len(blob); blob += cnt.tobytes(); pad()
    b["idx"] = len(blob); blob += idx.tobytes(); pad()
    b["val"] = len(blob); blob += val.tobytes(); pad()
    meta["boards"].append(b)
    print(f"board {k} (hid {bd['hid']}): {b['n']} frames, median {np.median(cnt):.0f} taxels/frame")
open(os.path.join(out_dir, "replay.bin"), "wb").write(bytes(blob))
json.dump(meta, open(os.path.join(out_dir, "replay.json"), "w"), indent=1)
print("replay.bin", len(blob), "bytes")
