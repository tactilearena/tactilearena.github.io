---
title: Paper
description: Scalable high-density tactile arenas for measuring ground-contact forces in freely moving animals. Authors, summary, citation and related work.
---

# Paper

## Scalable high-density tactile arenas for measuring ground-contact forces in freely moving animals

<p class="ta-authors"><strong>Weiwen Lu</strong><sup>1&ast;</sup>, <strong>Ariel Slepyan</strong><sup>2,3&ast;</sup>,
Pierce Perkins<sup>1</sup>, Alessandro Ascani Orsini<sup>4</sup>, Kiara Quinn<sup>1</sup>, Nitish V. Thakor<sup>1</sup></p>

<p class="ta-small"><sup>1</sup>Department of Biomedical Engineering, Johns Hopkins University ·
<sup>2</sup>Department of Electrical Engineering and Computer Science, MIT ·
<sup>3</sup>Department of Brain and Cognitive Sciences, MIT ·
<sup>4</sup>Department of Electrical Engineering, Johns Hopkins University ·
<sup>&ast;</sup>These authors contributed equally.</p>

**Preprint:** [bioRxiv](https://www.biorxiv.org/content/10.64898/2026.10.22.760735v1), posted 25 October 2026; doi:10.64898/2026.10.22.760735.

**Contact:** Weiwen Lu ([wlu33@jh.edu](mailto:wlu33@jh.edu)), Ariel Slepyan
([aslepyan@mit.edu](mailto:aslepyan@mit.edu)), Nitish V. Thakor ([nitish@jhu.edu](mailto:nitish@jhu.edu)).

## Abstract { #summary }

Understanding how animals physically interact with their environment is fundamental to studying movement,
sensorimotor control, and neurological function. Yet most behavioral measurement systems primarily capture movement
and posture, while direct measurements of contact forces often require specialized instrumentation or involve
trade-offs among spatial coverage, resolution, and acquisition speed. Here, we introduce a scalable tactile sensing
platform that transforms the surface beneath freely moving animals into a high-resolution contact-imaging
instrument. By combining modular sensor arrays with adaptive compressive tactile sampling, the platform provides
16,384 tactile sensing elements at 2-mm pitch across a 512&nbsp;&times;&nbsp;128-mm runway, with nominal 1 kHz
acquisition. Rather than exhaustively scanning the entire array, the system concentrates measurements around active
contacts, enabling high-speed sensing across an extended behavioral surface. Synchronized overhead video and a
camera-assisted analysis pipeline enable paw-resolved measurements of contact loading, stance dynamics, footprint
morphology, interlimb weight redistribution, and center-of-pressure trajectories. In a longitudinal rat model of
sciatic nerve injury, the platform detected reduced loading of the injured hindlimb and increased loading of the
contralateral limb, including changes that conventional gait timing measures underestimated. The modular
architecture, together with openly available hardware designs, software and data, provides an accessible framework
for studying the mechanical interactions underlying freely moving behavior, with potential applications across
neuroscience, injury, and motor recovery research.

## Citation { #cite }

<div class="ta-cite" markdown>

```bibtex
@article{lu2026tactilearena,
  title   = {Scalable high-density tactile arenas for measuring ground-contact forces in freely moving animals},
  author  = {Lu, Weiwen and Slepyan, Ariel and Perkins, Pierce and Ascani Orsini, Alessandro and Quinn, Kiara and Thakor, Nitish V.},
  journal = {bioRxiv},
  year    = {2026},
  doi     = {10.64898/2026.10.22.760735},
  url     = {https://www.biorxiv.org/content/10.64898/2026.10.22.760735v1}
}
```

</div>

## Supplementary videos { #videos }

Full-resolution files are available from the [GitHub release](https://github.com/tactilearena/tactilearena.github.io/releases/tag/supplementary-videos-v1); legends are provided in [`supplementary/README.md`](https://github.com/tactilearena/tactilearena.github.io/tree/main/supplementary).

<div class="ta-cards ta-cards--video" markdown>
<div class="ta-card" markdown>
<div class="ta-media"><video width="720" height="1280" controls muted playsinline preload="none" data-poster="../assets/video/assembly.jpg" aria-label="Supplementary Video 1: Assembly of the tactile runway"><source src="../assets/video/assembly.mp4" type="video/mp4"></video></div>
<div class="ta-card__body" markdown>
<span class="ta-card__num">SUPPLEMENTARY VIDEO 1</span>

### Assembly of the tactile runway

Connection of the sensor modules to their readout boards, alignment of the four arrays, application of the piezoresistive film and connection to the host computer.

[Download (full resolution)](https://github.com/tactilearena/tactilearena.github.io/releases/download/supplementary-videos-v1/SupplementaryVideo1_assembly.mp4){ .ta-more }
</div>
</div>
<div class="ta-card" markdown>
<div class="ta-media"><video width="1280" height="1000" controls muted playsinline preload="none" data-poster="../assets/video/pre-surgery.jpg" aria-label="Supplementary Video 2: Synchronized overhead video and paw-resolved plantar pressure during walking before sciatic nerve pinch"><source src="../assets/video/pre-surgery.mp4" type="video/mp4"></video></div>
<div class="ta-card__body" markdown>
<span class="ta-card__num">SUPPLEMENTARY VIDEO 2</span>

### Synchronized overhead video and paw-resolved plantar pressure during walking before sciatic nerve pinch

Rat 6, 11 February 2026: paw contacts labelled on the overhead video, with the plantar pressure distribution of each paw during stance. Playback at 0.25&times; real time.

[Download (full resolution)](https://github.com/tactilearena/tactilearena.github.io/releases/download/supplementary-videos-v1/SupplementaryVideo2_walking_before_surgery.mp4){ .ta-more }
</div>
</div>
<div class="ta-card" markdown>
<div class="ta-media"><video width="1280" height="1000" controls muted playsinline preload="none" data-poster="../assets/video/post-surgery.jpg" aria-label="Supplementary Video 3: Synchronized overhead video and paw-resolved plantar pressure during walking after sciatic nerve pinch"><source src="../assets/video/post-surgery.mp4" type="video/mp4"></video></div>
<div class="ta-card__body" markdown>
<span class="ta-card__num">SUPPLEMENTARY VIDEO 3</span>

### Synchronized overhead video and paw-resolved plantar pressure during walking after sciatic nerve pinch

Rat 4, 19 March 2026, nine days after left sciatic nerve pinch. Playback at 0.25&times; real time.

[Download (full resolution)](https://github.com/tactilearena/tactilearena.github.io/releases/download/supplementary-videos-v1/SupplementaryVideo3_walking_after_surgery.mp4){ .ta-more }
</div>
</div>
<div class="ta-card" markdown>
<div class="ta-media"><video width="1920" height="1080" controls muted playsinline preload="none" data-poster="../assets/video/supp4_sampling.jpg" aria-label="Supplementary Video 4: Adaptive tactile sampling during locomotion"><source src="../assets/video/supp4_sampling.mp4" type="video/mp4"></video></div>
<div class="ta-card__body" markdown>
<span class="ta-card__num">SUPPLEMENTARY VIDEO 4</span>

### Adaptive tactile sampling during locomotion

The firmware sampling loop applied to a simulated paw contact, followed by the recorded packets of all four modules during walking, displayed frame by frame.

[Download (full resolution)](https://github.com/tactilearena/tactilearena.github.io/releases/download/supplementary-videos-v1/SupplementaryVideo4_adaptive_tactile_sampling.mp4){ .ta-more }
</div>
</div>
<div class="ta-card" markdown>
<div class="ta-media"><video width="1920" height="1080" controls muted playsinline preload="none" data-poster="../assets/video/supp5_arena.jpg" aria-label="Supplementary Video 5: Reconfiguration of the sensor modules into an open-field arena"><source src="../assets/video/supp5_arena.mp4" type="video/mp4"></video></div>
<div class="ta-card__body" markdown>
<span class="ta-card__num">SUPPLEMENTARY VIDEO 5</span>

### Reconfiguration of the sensor modules into an open-field arena

Four modules tiled 2&nbsp;&times;&nbsp;2 form a 256&nbsp;&times;&nbsp;256&nbsp;mm arena of 128&nbsp;&times;&nbsp;128 taxels: a single rat walking, turning and rearing, recorded with overhead and side cameras, followed by three rats exploring the arena simultaneously.

[Download (full resolution)](https://github.com/tactilearena/tactilearena.github.io/releases/download/supplementary-videos-v1/SupplementaryVideo5_open_field_arena.mp4){ .ta-more }
</div>
</div>
</div>

## Related work { #related }

- A. Slepyan, D. Li, H. Cai, R. McGovern, A. Aug, S. Sankar, T. Tran, N. Thakor. *Adaptive compressive tactile
  subsampling: enabling high spatiotemporal resolution in scalable robotic skin.*
  [arXiv:2410.13847](https://arxiv.org/abs/2410.13847) (2024).
- A. Slepyan, L. Xing, R. Zhang, N. Thakor. *Single-pixel tactile skin via compressive sampling.*
  Communications Engineering (2026).
- A. Slepyan, Y. Luo, E. Levenshus, S. Sankar, A. Aug, M. Iskarous, N. Thakor. *Analog dual-tone
  multi-frequency signaling for scalable tactile skin with automatic data compression and a single-wire output.*
  IEEE Sensors Journal (2026).

## Ethics { #ethics }

All animal procedures were conducted under a protocol approved by the Johns Hopkins University Animal Care and Use
Committee (ACUC; protocol RA24M61, approved 11 March 2024).
