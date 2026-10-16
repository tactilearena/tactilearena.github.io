---
title: Data
description: All 85 runway recordings from the TactileArena study, with raw pressure packets, overhead video and the original annotations.
---

# Data

<p class="ta-lede">All 85 runway recordings analysed in the study, released under CC&nbsp;BY&nbsp;4.0, with the
annotations needed to reproduce the analyses.</p>

!!! note "Deposit being finalized"
    The recordings will be published on Zenodo at
    [doi:10.5281/zenodo.23286364](https://doi.org/10.5281/zenodo.23286364). The DOI is reserved and will resolve
    once the deposit is published.

## What is in the deposit { #contents }

- **Recordings:** one zip per recording (`<M-D-YYYY>_ratN.zip`, about 380&nbsp;MB each). Each holds the raw
  pressure packets from the four boards with the camera-frame timestamps on the same clock (MATLAB `.mat`), and
  the overhead video (MP4).
- **Annotations** (`annotations.zip`): camera-to-sensor homographies; blind manual paw labels (FL/FR/HL/HR)
  for 81 recordings; manually selected walking windows and the review decisions behind them; manually
  reviewed contacts over whole recordings, including standing; and body mass by rat and date.
- **Demo package** (`demo_2-24-2026_rat4.zip`, 415&nbsp;MB): one complete recording laid out like the full
  deposit, for the [pipeline demo](software.md#demo).

Processed outputs are not deposited; the code regenerates them.

```text
<data_root>/
  <M-D-YYYY>/runway/ratN/runway_tactile_data_*.mat   raw pressure packets (+ camera frame timestamps)
  <M-D-YYYY>/runway/ratN/camera_*.mp4                 overhead video
  annotations/
    recordings.csv                    the 85 analysed recordings (paths relative to data_root)
    homographies/                     camera -> sensor projective transform, one per recording
    blind_labels/                     manual FL/FR/HL/HR labels (blinded to the algorithm)
    mobile_bout_windows.csv           manually selected walking windows
    cop_trajectory_corrections.csv    keep/trim decisions that produced those windows
    corrected_contacts.csv            manually reviewed contacts over whole recordings
    mass.csv                          body mass by rat and date
```

## The study { #study }

Five male Lewis rats (12&ndash;16 weeks, 390&ndash;430&nbsp;g): three with a left sciatic nerve pinch and two
sham-operated, recorded before surgery and over the following two weeks. Each recording is a session of about 90&nbsp;s on
the runway with M&nbsp;=&nbsp;200, threshold 700 and digital potentiometer 100. Raw packets are the boards' own
output: for every frame, which taxels were read and their 12-bit values, including readings below threshold. See
[How it works](how-it-works.md#sampling) and the firmware README for the format.

## Reading a recording { #reading }

In each `.mat` file, `BoardN_timestamps`, `BoardN_pixel_indices` and `BoardN_pixel_values` hold one entry per
frame for each board, `BoardN_board_ids` the board's hardware ID, and `cameraK_frame_timestamps` the time of
every video frame on the same clock. A taxel index `i` is row `i // 32`, column `i % 32` for `i < 2048`, and
row `(i - 2048) // 32`, column `(i - 2048) % 32 + 32` otherwise. Boards are placed by hardware ID 4, 3, 2, 1 from
left to right along the runway. `site_tools/ta_frames.py` in the repository rebuilds pressure frames this way
in Python.
