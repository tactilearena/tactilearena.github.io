# Supplementary videos

Supplementary Videos 1–5 of Lu, Slepyan et al., *Scalable high-density tactile arenas for measuring ground-contact forces in freely moving animals*, bioRxiv (2026), [doi:10.64898/2026.10.22.760735](https://www.biorxiv.org/content/10.64898/2026.10.22.760735v1).

Full-quality files are attached to the
[supplementary-videos-v1 release](https://github.com/tactilearena/tactilearena.github.io/releases/tag/supplementary-videos-v1);
lighter copies play on the [website](https://tactilearena.github.io/paper/#videos). All are MP4 (H.264), without
audio. The scripts that produce them are in `site_tools/` (see its README).

| # | File | Length |
|---|---|---|
| 1 | [SupplementaryVideo1_assembly.mp4](https://github.com/tactilearena/tactilearena.github.io/releases/download/supplementary-videos-v1/SupplementaryVideo1_assembly.mp4) | 1:33 |
| 2 | [SupplementaryVideo2_walking_before_surgery.mp4](https://github.com/tactilearena/tactilearena.github.io/releases/download/supplementary-videos-v1/SupplementaryVideo2_walking_before_surgery.mp4) | 0:13 |
| 3 | [SupplementaryVideo3_walking_after_surgery.mp4](https://github.com/tactilearena/tactilearena.github.io/releases/download/supplementary-videos-v1/SupplementaryVideo3_walking_after_surgery.mp4) | 0:26 |
| 4 | [SupplementaryVideo4_adaptive_tactile_sampling.mp4](https://github.com/tactilearena/tactilearena.github.io/releases/download/supplementary-videos-v1/SupplementaryVideo4_adaptive_tactile_sampling.mp4) | 0:46 |
| 5 | [SupplementaryVideo5_open_field_arena.mp4](https://github.com/tactilearena/tactilearena.github.io/releases/download/supplementary-videos-v1/SupplementaryVideo5_open_field_arena.mp4) | 0:40 |

## Legends

**Supplementary Video 1 | Assembly of the tactile runway.** Each 64 × 64 sensor module is connected to its readout board through its two flexible tails; the four modules are aligned edge to edge, covered with a piezoresistive film, and connected to the host computer. On-screen captions describe each step.

**Supplementary Video 2 | Synchronized overhead video and paw-resolved plantar pressure during walking before sciatic nerve pinch.** Overhead video of a rat walking on the runway before surgery (rat 6, 11 February 2026), with each paw contact labelled by the analysis pipeline (FL, FR, HL, HR). The lower panels show the plantar pressure distribution of each paw during stance as surfaces of raw taxel values. Playback at 0.25× real time.

**Supplementary Video 3 | Synchronized overhead video and paw-resolved plantar pressure during walking after sciatic nerve pinch.** As Supplementary Video 2, nine days after left sciatic nerve pinch (rat 4, 19 March 2026). Playback at 0.25× real time.

**Supplementary Video 4 | Adaptive tactile sampling during locomotion.** First, one acquisition frame of a single 64 × 64 module, shown read by read: the readout firmware's sampling loop applied to a simulated paw contact, which re-reads the previous frame's active taxels, performs a coarse-to-fine background scan and recursively reads the 3 × 3 neighbourhood of every reading above threshold until M = 200 taxels have been read. Then, recorded packets from all four modules during walking (rat 4, 24 February 2026), displayed frame by frame and at approximately 1/8 of real time. Black, not read in that frame; grey, read and below threshold (T = 700); colour, read and above threshold.

**Supplementary Video 5 | Reconfiguration of the sensor modules into an open-field arena.** Four 64 × 64 modules tiled 2 × 2 form a 256 × 256 mm open-field arena of 128 × 128 taxels. First, a single rat walking, turning and rearing (rat 4, 24 February 2026; M = 200, T = 700), shown with the tactile map, an overhead camera and a side camera at 0.75× real time. Then, three rats exploring the arena simultaneously, shown with the tactile map and the overhead camera.
