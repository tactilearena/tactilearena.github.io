"""Tail-base CNN (RGB + body mask in board space -> heatmap): annotate, train, predict."""

from __future__ import annotations

import argparse
import csv
import math
import random
from pathlib import Path

import cv2
import numpy as np
import torch
from torch import nn
from torch.utils.data import DataLoader, Dataset


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open("r", newline="", encoding="utf-8-sig") as f:
        return list(csv.DictReader(f))


def write_csv(path: Path, rows: list[dict[str, object]], fields: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)


def load_input(rgb_path: str, mask_path: str) -> np.ndarray | None:
    bgr = cv2.imread(rgb_path)
    mask = cv2.imread(mask_path, cv2.IMREAD_GRAYSCALE)
    if bgr is None or mask is None:
        return None
    rgb = cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB)
    return np.concatenate([rgb.astype(np.float32) / 255, mask[..., None].astype(np.float32) / 255], 2)


# --- model ---------------------------------------------------------------

class TailNet(nn.Module):
    def __init__(self) -> None:
        super().__init__()
        self.encoder = nn.Sequential(
            nn.Conv2d(4, 24, 3, padding=1), nn.ReLU(), nn.BatchNorm2d(24),
            nn.Conv2d(24, 32, 3, stride=2, padding=1), nn.ReLU(),
            nn.Conv2d(32, 48, 3, stride=2, padding=1), nn.ReLU(),
            nn.Conv2d(48, 64, 3, padding=1), nn.ReLU())
        self.heat = nn.Sequential(
            nn.ConvTranspose2d(64, 32, 4, stride=2, padding=1), nn.ReLU(),
            nn.ConvTranspose2d(32, 16, 4, stride=2, padding=1), nn.ReLU(),
            nn.Conv2d(16, 1, 1))

    def forward(self, x):
        return self.heat(self.encoder(x))


# --- annotate --------------------------------------------------------------

def annotate(args) -> None:
    rows = read_csv(args.manifest)
    labels = {}
    if args.labels.exists():
        labels = {r["sample_id"]: {"sample_id": r["sample_id"], "tail_base_x": r["tail_base_x"],
                                   "tail_base_y": r["tail_base_y"], "status": r.get("status", "labeled")}
                  for r in read_csv(args.labels)}
    fields = ["sample_id", "tail_base_x", "tail_base_y", "status"]
    state: list[tuple[int, int]] = []
    window = "Tail-base labels: click TAIL BASE | enter/space accept | u undo | s skip | q save/quit"

    def click(event: int, x: int, y: int, _flags: int, _param: object) -> None:
        if event == cv2.EVENT_LBUTTONDOWN and not state:
            state.append((x, y))

    cv2.namedWindow(window, cv2.WINDOW_NORMAL)
    cv2.setMouseCallback(window, click)
    for i, row in enumerate(rows):
        sample_id = row["sample_id"]
        if sample_id in labels:
            continue
        image = cv2.imread(row["rgb_path"])
        if image is None:
            print(f"Skipping unreadable image: {row['rgb_path']}")
            continue
        state.clear()
        while True:
            shown = image.copy()
            if state:
                cv2.drawMarker(shown, state[0], (0, 255, 255), cv2.MARKER_CROSS, 14, 2)
            cv2.putText(shown, f"{i + 1}/{len(rows)}  {sample_id}", (5, 18),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.48, (255, 255, 255), 1)
            cv2.imshow(window, shown)
            key = cv2.waitKey(20) & 0xFF
            if key in (ord("q"), 27):
                write_csv(args.labels, list(labels.values()), fields)
                cv2.destroyAllWindows()
                return
            if key == ord("u") and state:
                state.pop()
            if key == ord("s"):
                labels[sample_id] = {"sample_id": sample_id, "tail_base_x": "", "tail_base_y": "", "status": "skipped"}
                break
            if key in (13, 32) and len(state) == 1:
                labels[sample_id] = {"sample_id": sample_id, "tail_base_x": state[0][0],
                                     "tail_base_y": state[0][1], "status": "labeled"}
                break
        write_csv(args.labels, list(labels.values()), fields)
    write_csv(args.labels, list(labels.values()), fields)
    cv2.destroyAllWindows()


# --- train -----------------------------------------------------------------

class TailDataset(Dataset):
    def __init__(self, items: list[dict[str, str]], augment: bool, heat_sigma: float) -> None:
        self.items, self.augment, self.heat_sigma = items, augment, heat_sigma

    def __len__(self) -> int:
        return len(self.items)

    def __getitem__(self, index: int):
        r = self.items[index]
        rgb = cv2.cvtColor(cv2.imread(r["rgb_path"]), cv2.COLOR_BGR2RGB)
        mask = cv2.imread(r["mask_path"], cv2.IMREAD_GRAYSCALE)
        h, w = mask.shape
        bx, by = float(r["tail_base_x"]), float(r["tail_base_y"])
        if self.augment and random.random() < 0.5:
            rgb, mask = rgb[:, ::-1].copy(), mask[:, ::-1].copy()
            bx = w - 1 - bx
        yy, xx = np.mgrid[:h, :w]
        heat = np.exp(-((xx - bx) ** 2 + (yy - by) ** 2) / (2 * self.heat_sigma ** 2)).astype(np.float32)
        x = np.concatenate([rgb.astype(np.float32) / 255, mask[..., None].astype(np.float32) / 255], 2)
        return (torch.from_numpy(x.transpose(2, 0, 1)), torch.from_numpy(heat[None]),
                torch.tensor([bx, by], dtype=torch.float32))


def location_error(logits: torch.Tensor, target_xy: torch.Tensor) -> torch.Tensor:
    flat = logits.flatten(1).argmax(1)
    w = logits.shape[-1]
    pred = torch.stack([(flat % w).float(), (flat // w).float()], 1)
    return torch.linalg.vector_norm(pred - target_xy, dim=1).mean()


def soft_argmax_xy(logits: torch.Tensor, beta: float = 10.0) -> torch.Tensor:
    batch, _, height, width = logits.shape
    probabilities = torch.softmax(logits.reshape(batch, -1) * beta, dim=1)
    x_coords = torch.arange(width, device=logits.device, dtype=logits.dtype)
    y_coords = torch.arange(height, device=logits.device, dtype=logits.dtype)
    grid_y, grid_x = torch.meshgrid(y_coords, x_coords, indexing="ij")
    return torch.stack([(probabilities * grid_x.reshape(1, -1)).sum(dim=1),
                        (probabilities * grid_y.reshape(1, -1)).sum(dim=1)], dim=1)


def localization_loss(logits, target_heat, target_xy, coord_weight, heat_positive_weight):
    heat_probabilities = torch.sigmoid(logits)
    heat_weights = 1.0 + heat_positive_weight * target_heat
    heat_loss = ((heat_probabilities - target_heat).square() * heat_weights).mean()
    pred_xy = soft_argmax_xy(logits)
    scale = target_xy.new_tensor([logits.shape[-1] - 1, logits.shape[-2] - 1])
    coord_loss = nn.functional.smooth_l1_loss(pred_xy / scale, target_xy / scale)
    return heat_loss + coord_weight * coord_loss, heat_loss, coord_loss


def train(args) -> None:
    random.seed(args.seed); np.random.seed(args.seed); torch.manual_seed(args.seed)
    manifest = {r["sample_id"]: r for r in read_csv(args.manifest)}
    data = [{**manifest[r["sample_id"]], **r} for r in read_csv(args.labels)
            if r["sample_id"] in manifest and r.get("status", "labeled") != "skipped"
            and r.get("tail_base_x", "") and r.get("tail_base_y", "")]
    if len(data) < 20:
        raise ValueError(f"Need at least 20 labeled frames; found {len(data)}")
    for r in data:
        image = cv2.imread(r["rgb_path"])
        if image is None:
            raise ValueError(f"{r['sample_id']}: unreadable image")
        h, w = image.shape[:2]
        if not (0 <= float(r["tail_base_x"]) < w and 0 <= float(r["tail_base_y"]) < h):
            raise ValueError(f"{r['sample_id']}: label outside the {w}x{h} board image")
    recordings = sorted({r["output_name"] for r in data})
    random.shuffle(recordings)
    val_names = set(recordings[:max(1, round(0.2 * len(recordings)))])
    train_rows = [r for r in data if r["output_name"] not in val_names]
    val_rows = [r for r in data if r["output_name"] in val_names]
    loaders = {"train": DataLoader(TailDataset(train_rows, True, args.heat_sigma), args.batch_size, shuffle=True),
               "val": DataLoader(TailDataset(val_rows, False, args.heat_sigma), args.batch_size)}
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    model = TailNet().to(device)
    opt = torch.optim.AdamW(model.parameters(), lr=1e-3, weight_decay=1e-4)
    history, best = [], math.inf
    args.out_dir.mkdir(parents=True, exist_ok=True)
    for epoch in range(1, args.epochs + 1):
        entry = {"epoch": epoch}
        for phase in ("train", "val"):
            model.train(phase == "train")
            sums = np.zeros(4); count = 0
            for x, heat, xy in loaders[phase]:
                x, heat, xy = [v.to(device) for v in (x, heat, xy)]
                with torch.set_grad_enabled(phase == "train"):
                    logits = model(x)
                    loss, heat_loss, coord_loss = localization_loss(logits, heat, xy, args.coord_weight,
                                                                    args.heat_positive_weight)
                    if phase == "train":
                        opt.zero_grad(); loss.backward(); opt.step()
                sums += [loss.item() * len(x), heat_loss.item() * len(x), coord_loss.item() * len(x),
                         location_error(logits, xy).item() * len(x)]
                count += len(x)
            entry.update({f"{phase}_loss": sums[0] / count, f"{phase}_heatmap_loss": sums[1] / count,
                          f"{phase}_coordinate_loss": sums[2] / count,
                          f"{phase}_location_error_px": sums[3] / count})
        history.append(entry)
        print(f"{epoch:03d} loss {entry['train_loss']:.4f}/{entry['val_loss']:.4f} "
              f"error {entry['val_location_error_px']:.2f}px")
        if entry["val_location_error_px"] < best:
            best = entry["val_location_error_px"]
            torch.save({"model": model.state_dict(), "input_channels": 4}, args.out_dir / "best_tail_detector.pt")
    write_csv(args.out_dir / "training_history.csv", history, list(history[0].keys()))
    (args.out_dir / "split_summary.txt").write_text(f"train={len(train_rows)}\nvalidation={len(val_rows)}\n",
                                                    encoding="utf-8")


# --- predict ---------------------------------------------------------------

def local_soft_argmax_xy(logits_hw: torch.Tensor, peak_y: int, peak_x: int, window_radius: int,
                         beta: float = 10.0) -> tuple[float, float]:
    """Soft-argmax inside a window around the hard-argmax peak, so a second,
    distant peak of similar strength cannot pull the estimate between them."""
    height, width = logits_hw.shape
    y0, y1 = max(0, peak_y - window_radius), min(height, peak_y + window_radius + 1)
    x0, x1 = max(0, peak_x - window_radius), min(width, peak_x + window_radius + 1)
    probabilities = torch.softmax(logits_hw[y0:y1, x0:x1].reshape(-1) * beta, dim=0)
    y_coords = torch.arange(y0, y1, device=logits_hw.device, dtype=logits_hw.dtype)
    x_coords = torch.arange(x0, x1, device=logits_hw.device, dtype=logits_hw.dtype)
    grid_y, grid_x = torch.meshgrid(y_coords, x_coords, indexing="ij")
    return float((probabilities * grid_x.reshape(-1)).sum()), float((probabilities * grid_y.reshape(-1)).sum())


def predict(args) -> None:
    rows = read_csv(args.manifest)
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    model = TailNet().to(device)
    state = torch.load(args.checkpoint, map_location=device, weights_only=True)
    model.load_state_dict(state["model"])
    model.eval()
    out: list[dict[str, object]] = []
    with torch.no_grad():
        for start in range(0, len(rows), args.batch_size):
            batch, tensors = [], []
            for row in rows[start:start + args.batch_size]:
                x = load_input(row["rgb_path"], row["mask_path"])
                if x is not None:
                    tensors.append(torch.from_numpy(x.transpose(2, 0, 1))); batch.append(row)
            if not tensors:
                continue
            logits = model(torch.stack(tensors).to(device))
            heat_prob = torch.sigmoid(logits)[:, 0].cpu().numpy()
            for row, heatmap, logit_hw in zip(batch, heat_prob, logits[:, 0]):
                peak_y, peak_x = np.unravel_index(int(np.argmax(heatmap)), heatmap.shape)
                if args.decode == "hard":
                    px, py = float(peak_x), float(peak_y)
                else:
                    px, py = local_soft_argmax_xy(logit_hw, peak_y, peak_x, args.window_radius)
                out.append({"frame_index": int(float(row["frame_index"])), "time_s": float(row.get("time_s", "nan")),
                            "tailbase_x_px": px, "tailbase_y_px": py,
                            "tailbase_confidence": float(heatmap[peak_y, peak_x])})
    write_csv(args.out, out, ["frame_index", "time_s", "tailbase_x_px", "tailbase_y_px", "tailbase_confidence"])
    print(f"Wrote {len(out)} tail-base predictions: {args.out}")


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    sub = p.add_subparsers(dest="cmd", required=True)
    a = sub.add_parser("annotate"); a.add_argument("--manifest", type=Path, required=True)
    a.add_argument("--labels", type=Path, required=True)
    t = sub.add_parser("train"); t.add_argument("--manifest", type=Path, required=True)
    t.add_argument("--labels", type=Path, required=True); t.add_argument("--out-dir", type=Path, required=True)
    t.add_argument("--epochs", type=int, default=100); t.add_argument("--batch-size", type=int, default=16)
    t.add_argument("--seed", type=int, default=23); t.add_argument("--heat-sigma", type=float, default=3.0)
    t.add_argument("--coord-weight", type=float, default=2.0)
    t.add_argument("--heat-positive-weight", type=float, default=0.0)
    q = sub.add_parser("predict"); q.add_argument("--manifest", type=Path, required=True)
    q.add_argument("--checkpoint", type=Path, required=True); q.add_argument("--out", type=Path, required=True)
    q.add_argument("--batch-size", type=int, default=32); q.add_argument("--window-radius", type=int, default=15)
    q.add_argument("--decode", choices=["soft", "hard"], default="soft")
    args = p.parse_args()
    {"annotate": annotate, "train": train, "predict": predict}[args.cmd](args)


if __name__ == "__main__":
    main()
