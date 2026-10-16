---
title: Software
description: Acquisition firmware and recording code, and the MATLAB/Python pipeline that turns raw pressure packets and overhead video into paw-labelled stance events and calibrated loading.
---

# Software

<p class="ta-lede">Everything from the readout boards to paw-labelled stance events is in the
<a href="https://github.com/tactilearena/tactilearena.github.io">repository</a>, under the MIT licence. Its
README is the full reference; this page is the short version.</p>

## What is in the repository { #layout }

```text
acquisition/   record_runway.py         four boards + two overhead cameras on one clock -> .mat + .mp4
               live_view_runway.py      live pressure map (no recording)
               firmware/                readout-board firmware (Teensy 4.x; set BOARD_ID per board)
pipeline/      gait_config.m            paths and study settings (edit this first)
               s1_prepare_recordings.m  background models; video choice and platform corners for new data
               s2_detect_contacts.m     tail-base CNN + contact detector -> pressure movie, contacts
               s3_find_mobile_bouts.m   whole-animal COP trace and walking bouts (+ review window)
               s4_label_paws.m          FL/FR/HL/HR stance events inside the walking bouts (+ labelled video)
               s5_calibrate_to_grams.m  summed taxel response -> mass-equivalent grams
tailbase/      tailbase_cnn.py          tail-base localizer: annotate / train / predict
demo/          run_demo.m               runs the pipeline on the demo recording and checks the result
data/          tailbase_model/, calibration_0_450/, platform_sheet_template.mat
docs/          this website (MkDocs); site_tools/ makes its figures and videos from the recordings
```

## Requirements { #requirements }

- **MATLAB** (tested on R2023b) with the Image Processing, Signal Processing, and Statistics and Machine Learning toolboxes.
- **Python 3** for the tail-base network: `pip install -r requirements.txt` (NumPy, OpenCV, PyTorch). A GPU is not needed: on the demo recording a CPU-only run took the same time and gave the same labels.
- **For recording only:** the readout boards, a computer with four USB ports and the overhead cameras, plus `pyserial` and `scipy`.

## Run the demo { #demo }

The demo package holds one complete recording (rat 4, 24 February 2026, two weeks before surgery: an 85&nbsp;s
session with five runway crossings) in the same layout as the full data deposit (see [Data](data.md)).

```matlab
setenv('GAIT_PYTHON', 'C:\path\to\python.exe')   % Python with PyTorch, if not on the PATH
addpath('<repo>/demo')
run_demo('C:\gait_demo\data', 'C:\gait_demo\work')
```

It runs stages s1&ndash;s4 and writes the 5 walking windows, the 58 labelled stance events and a labelled video of
each walking window. It then compares the tables with `demo/expected/` and ends with `DEMO PASSED`. It takes
about 9 minutes on a 32-thread desktop.

## The pipeline, stage by stage { #pipeline }

| Stage | Does | Output |
|---|---|---|
| **s1** prepare | Median background image of each overhead video; for new data, pick the video and click the four platform corners (the sensor corners and homography follow from the platform template) | background model, homography |
| **s2** contacts | Background-subtract and warp video into the 256&nbsp;&times;&nbsp;64 board space, localize the tail base, rebuild the pressure movie from the board packets, segment contacts, collect camera votes | pressure movie (~120 frames/s), contacts |
| **s3** walking bouts | Whole-animal centre of pressure at ~100&nbsp;Hz, candidate walking bouts from its speed, a review window to keep or trim them | COP trace, walking windows |
| **s4** paws | Re-segment stance contacts in each window and assign FL/FR/HL/HR from position relative to the smoothed COP and heading, plus camera votes; Viterbi left/right decoding | stance events (+ labelled video) |
| **s5** grams | Convert summed responses to mass-equivalent grams with each board's calibration curve | loads in grams |

Conventions: time in seconds on the recording's shared clock; positions in taxels on the 64&nbsp;&times;&nbsp;256 grid
(one taxel = 2&nbsp;mm, boards 4-3-2-1 from left to right); pressure in raw 12-bit counts until converted.

## Website and media { #site }

This website is built with [MkDocs Material](https://squidfunk.github.io/mkdocs-material/) from `docs/`. The
scripts in `site_tools/` rebuild its pressure videos and sampling explainers from a raw recording, using the same
frame reconstruction as the pipeline (each board's latest packet, boards 4-3-2-1 from left to right).
