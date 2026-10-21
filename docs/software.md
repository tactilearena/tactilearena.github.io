---
title: Software
description: Acquisition firmware and recording software, and the MATLAB/Python pipeline that converts raw pressure packets and overhead video into paw-labelled stance events and calibrated loading.
---

# Software

<p class="ta-lede">The complete acquisition and analysis software, from the readout firmware to paw-labelled stance
events, is available in the <a href="https://github.com/tactilearena/tactilearena.github.io">repository</a> under the
MIT License. This page summarizes its organization; the repository README provides the full reference. Scripts
used to compute the gait metrics and statistical analyses reported in the manuscript are available from the
corresponding authors upon request.</p>

## Repository structure { #layout }

| Folder | Contents |
|---|---|
| `acquisition/` | `record_runway.py`: synchronized recording of the four boards and the overhead and side cameras (`.mat` and `.mp4`); `live_view_runway.py`: live pressure map; `firmware/`: readout-board firmware (Teensy 4.1) |
| `pipeline/` | `gait_config.m`: paths and study settings; stages `s1`&ndash;`s5` (below) |
| `tailbase/` | `tailbase_cnn.py`: tail-base localization (annotation, training and prediction) |
| `demo/` | `run_demo.m`: runs the pipeline on the demonstration recording and verifies the output |
| `data/` | pretrained tail-base model, calibration curves and the platform template |
| `hardware/` | KiCad sources, fabrication files and bill of materials (CERN-OHL-P-2.0) |
| `docs/`, `site_tools/` | this website and the scripts that generate its figures and videos from the recordings |

## Requirements { #requirements }

- **MATLAB** (tested with R2023b) with the Image Processing, Signal Processing, and Statistics and Machine Learning toolboxes.
- **Python 3** for the tail-base network: `pip install -r requirements.txt` (NumPy, OpenCV, PyTorch). A GPU is not required; on the demonstration recording, a CPU-only run required the same time and produced identical labels.
- **Acquisition only:** the readout boards, a host computer with four USB ports and the two cameras (overhead and side), together with `pyserial` and `scipy`.

## Demonstration workflow { #demo }

The demonstration package contains one complete recording (rat 4, 24 February 2026, two weeks before surgery; an
85-s session with five runway traversals) organized in the same structure as the full data deposit (see
[Data](data.md)).

```matlab
setenv('GAIT_PYTHON', 'C:\path\to\python.exe')   % Python with PyTorch, if not on the PATH
addpath('<repo>/demo')
run_demo('C:\gait_demo\data', 'C:\gait_demo\work')
```

The workflow runs stages s1&ndash;s4 and writes the 5 walking windows, the 58 labelled stance events and a labelled
video of each walking window. It then compares the tables with the reference outputs in `demo/expected/` and
reports `DEMO PASSED` on success. The run requires approximately 9 minutes on a 32-thread workstation.

## Pipeline stages { #pipeline }

| Stage | Operation | Output |
|---|---|---|
| **s1** Preparation | Median background image of each overhead video; for new data, video selection and annotation of the four platform corners (sensor corners and homography follow from the platform template) | background model, homography |
| **s2** Contact detection | Background subtraction and warping of video into the 256&nbsp;&times;&nbsp;64 board space; tail-base localization; reconstruction of the pressure movie from the board packets; contact segmentation; camera-derived votes | pressure movie (~120 frames/s), contacts |
| **s3** Walking bouts | Whole-animal centre of pressure at ~100&nbsp;Hz; candidate walking bouts from its speed; review interface to retain or trim candidates | COP trace, walking windows |
| **s4** Paw assignment | Re-segmentation of stance contacts within each window and assignment to FL/FR/HL/HR from position relative to the smoothed COP and heading, with camera votes; Viterbi decoding of left/right sequences | stance events (with labelled video) |
| **s5** Calibration | Conversion of summed responses to mass-equivalent grams with the calibration curve of each board | loads in grams |

Conventions: time in seconds on the shared recording clock; positions in taxels on the 64&nbsp;&times;&nbsp;256 grid
(one taxel = 2&nbsp;mm; boards 4-3-2-1 from left to right); pressure in raw 12-bit counts until calibrated.

## Website and media { #site }

This website is built with [MkDocs Material](https://squidfunk.github.io/mkdocs-material/) from `docs/`. The scripts
in `site_tools/` regenerate its pressure videos, supplementary videos and sampling displays from the raw recordings,
using the same frame reconstruction as the analysis pipeline (most recent packet of each board; boards 4-3-2-1 from
left to right).
