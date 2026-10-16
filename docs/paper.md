---
title: Paper
description: Scalable high-density tactile arenas for measuring ground-contact forces in freely moving animals. Authors, summary, citation and related work.
---

# Paper

## Scalable high-density tactile arenas for measuring ground-contact forces in freely moving animals

Weiwen Lu<sup>1*</sup>, Ariel Slepyan<sup>2,3*</sup>, Pierce Perkins<sup>1</sup>, Alessandro Ascani
Orsini<sup>4</sup>, Kiara Quinn<sup>1</sup>, Nitish V. Thakor<sup>1</sup>

<p class="ta-small"><sup>1</sup>Department of Biomedical Engineering, Johns Hopkins University ·
<sup>2</sup>Department of Electrical Engineering and Computer Science, MIT ·
<sup>3</sup>Department of Brain and Cognitive Sciences, MIT ·
<sup>4</sup>Department of Electrical Engineering, Johns Hopkins University ·
<sup>*</sup>Equal contribution</p>

**Status:** manuscript in preparation.

**Contact:** Weiwen Lu ([wlu33@jh.edu](mailto:wlu33@jh.edu)), Ariel Slepyan
([aslepyan@mit.edu](mailto:aslepyan@mit.edu)), Nitish V. Thakor ([nitish@jhu.edu](mailto:nitish@jhu.edu)).

## Summary { #summary }

Behavioural measurements in freely moving animals mostly describe movement: where the body and limbs are, and
when paws touch down. How an animal distributes its weight, transfers load between contacts and pushes on its
surroundings is a separate quantity that video can only infer indirectly.

We present a scalable tactile platform that turns the floor of an arena into a high-resolution contact-measurement
instrument. Four modular sensor sheets form a 512&nbsp;&times;&nbsp;128&nbsp;mm runway with 16,384 taxels at 2&nbsp;mm pitch,
read at a nominal 1&nbsp;kHz. Adaptive compressive sampling makes this combination of area, density and speed
possible: each readout board concentrates its measurements around active contacts instead of scanning every
taxel. Overhead video recorded on the same clock supplies body position and orientation, and a camera-assisted
pipeline assigns contacts to paws, correctly labelling 93.3% of 2,469 manually annotated contacts within curated
walking windows.

In rats followed for two weeks after a sciatic nerve pinch, the platform showed that animals kept placing the
injured hind paw while carrying much less weight on it. The injured-to-contralateral hindpaw duty-factor ratio
fell by about a third, while the time-integrated loading ratio fell by about 60%. Loading shifted to the
opposite hind paw, and contact morphology changed. High-rate sampling preserved short stance events and
within-step loading dynamics that downsampling degrades.

## Cite { #cite }

<div class="ta-cite" markdown>

```bibtex
@misc{tactilearena2026,
  title  = {Scalable high-density tactile arenas for measuring ground-contact forces in freely moving animals},
  author = {Lu, Weiwen and Slepyan, Ariel and Perkins, Pierce and Ascani Orsini, Alessandro and Quinn, Kiara and Thakor, Nitish V.},
  year   = {2026},
  note   = {Manuscript in preparation},
  url    = {https://tactilearena.github.io}
}
```

</div>

## Related work from our groups { #related }

- A. Slepyan, D. Li, H. Cai, R. McGovern, A. Aug, S. Sankar, T. Tran, N. Thakor. *Adaptive compressive tactile
  subsampling: enabling high spatiotemporal resolution in scalable robotic skin.*
  [arXiv:2410.13847](https://arxiv.org/abs/2410.13847) (2024).
- A. Slepyan, L. Xing, R. Zhang, N. Thakor. *Single-pixel tactile skin via compressive sampling.*
  Communications Engineering (2026).
- A. Slepyan, Y. Luo, E. Levenshus, S. Sankar, A. Aug, M. Iskarous, N. Thakor. *Analog dual-tone
  multi-frequency signaling for scalable tactile skin with automatic data compression and a single-wire output.*
  IEEE Sensors Journal (2026).

## Animal work { #ethics }

Animal procedures were performed under protocol RA24M61.
