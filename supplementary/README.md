# Supplementary videos

Full-quality files are attached to the
[supplementary-videos-v1 release](https://github.com/tactilearena/tactilearena.github.io/releases/tag/supplementary-videos-v1);
lighter copies play on the [website](https://tactilearena.github.io/paper/#videos). All are MP4 (H.264), without
audio. Videos 4 and 5 are made from the raw recordings by `site_tools/make_supp_sampling.py` and
`site_tools/make_supp_square.py`.

| # | File | Length |
|---|---|---|
| 1 | [SupplementaryVideo1_assembly.mp4](https://github.com/tactilearena/tactilearena.github.io/releases/download/supplementary-videos-v1/SupplementaryVideo1_assembly.mp4) | 1:33 |
| 2 | [SupplementaryVideo2_walking_before_surgery.mp4](https://github.com/tactilearena/tactilearena.github.io/releases/download/supplementary-videos-v1/SupplementaryVideo2_walking_before_surgery.mp4) | 0:13 |
| 3 | [SupplementaryVideo3_walking_after_surgery.mp4](https://github.com/tactilearena/tactilearena.github.io/releases/download/supplementary-videos-v1/SupplementaryVideo3_walking_after_surgery.mp4) | 0:26 |
| 4 | [SupplementaryVideo4_adaptive_sampling.mp4](https://github.com/tactilearena/tactilearena.github.io/releases/download/supplementary-videos-v1/SupplementaryVideo4_adaptive_sampling.mp4) | 0:46 |
| 5 | [SupplementaryVideo5_open_arena_demo.mp4](https://github.com/tactilearena/tactilearena.github.io/releases/download/supplementary-videos-v1/SupplementaryVideo5_open_arena_demo.mp4) | 0:40 |

## Legends

**Supplementary Video 1 | Assembling the tactile runway.** The flexible tails of each 64 × 64 sensor module are
inserted into the connectors of its readout board, the four arrays are aligned edge to edge, covered with
piezoresistive film and a waterproof cloth, and the readout boards are connected to the host computer. On-screen
captions describe each step.

**Supplementary Video 2 | Paw-resolved pressure during walking before surgery.** Overhead video of rat 6 on
11 February 2026 (before surgery) with each detected paw contact labelled (FL, FR, HL, HR). Below, the pressure under
each paw while it is in stance, shown as a surface of raw taxel values. 0.25× real time.

**Supplementary Video 3 | Paw-resolved pressure during walking after sciatic nerve pinch.** As Supplementary Video 2,
for rat 4 on 19 March 2026, nine days after left sciatic nerve pinch. 0.25× real time.

**Supplementary Video 4 | Adaptive sampling, frame by frame.** First, one frame of one 64 × 64 module, read by read:
a simulation of the readout firmware's sampling loop on a simulated paw (re-reading the previous frame's contacts, a
coarse-to-fine background scan, and recursive reads of the 3 × 3 neighbours of every reading above threshold, until
M = 200 taxels have been read). Then the recorded packets of all four boards from a walking rat (24 February 2026,
rat 4), frame by frame and at about 1/8 of real time. Black, not read in that frame; grey, read and below threshold
(T = 700); colour, read and above threshold.

**Supplementary Video 5 | The same modules as an open arena (demonstration; not analysed).** Four modules tiled
2 × 2 (128 × 128 taxels over 256 × 256 mm) under a rat walking, turning and rearing, recorded with the study's
settings (24 February 2026, rat 4; M = 200, T = 700), with overhead and side cameras; 0.75× real time. Followed by
three rats on the same 2 × 2 arena in a development recording made before the study (November 2025) with an earlier
readout configuration.
