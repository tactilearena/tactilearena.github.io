# TactileArena

**Scalable high-density tactile arenas for measuring ground-contact forces in freely moving animals**
Weiwen Lu\*, Ariel Slepyan\*, Pierce Perkins, Alessandro Ascani Orsini, Kiara Quinn, Nitish V. Thakor (\*equal contribution).
Johns Hopkins University and MIT. Manuscript in preparation.

**Website: <https://tactilearena.github.io>** · [How it works](https://tactilearena.github.io/how-it-works/) · [Build guide](https://tactilearena.github.io/build/) · [Data](https://tactilearena.github.io/data/)

TactileArena transforms the floor into a sensor. A modular surface of 16,384 pressure-sensitive taxels (2-mm pitch, 512 × 128 mm, nominal 1 kHz) records where, when and with what force a freely moving animal contacts the ground, synchronized with overhead video and without instrumentation of the animal. Each readout board measures 200 of its module's 4,096 taxels per frame and concentrates these measurements on active contacts (adaptive compressive sampling), enabling this combination of sensing area, spatial density and acquisition speed.

The runway is a 64 × 256 piezoresistive array (four 64 × 64 modules, each with its own readout board) under a walking surface, recorded together with overhead cameras. This repository holds the readout firmware, the synchronized recording code, the pipeline that takes each recording from raw sensor packets to paw-labeled (FL/FR/HL/HR) stance events and mass-equivalent loading, and the project website (`docs/`).

## Repository layout

```
acquisition/   record_runway.py         four boards + two overhead cameras on one clock -> .mat + .mp4
               live_view_runway.py      live pressure map (no recording)
               firmware/                readout-board firmware (Teensy 4.1; set BOARD_ID per board)
pipeline/      gait_config.m            paths and study settings (edit this first)
               s1_prepare_recordings.m  background models; video choice and platform corners for new data
               s2_detect_contacts.m     tail-base CNN + contact detector -> pressure movie, contacts
               peak_seed_contact_detector.m  the contact detector (called by s2)
               s3_find_mobile_bouts.m   whole-animal COP trace and walking bouts (+ review window)
               s4_label_paws.m          FL/FR/HL/HR stance events inside the walking bouts (+ labeled video)
               s5_calibrate_to_grams.m  summed taxel response -> mass-equivalent grams
tailbase/      tailbase_cnn.py          tail-base localizer: annotate / train / predict
demo/          run_demo.m               runs the pipeline on the demo recording and checks the result
               expected/                expected walking windows and stance events
data/          tailbase_model/          trained tail-base CNN (best_tail_detector.pt) and its training history
               calibration_0_450/       per-board calibration curves (calibration_0_450.json)
               platform_sheet_template.mat   sensor position relative to the platform corners
hardware/      KiCad sources, fabrication Gerbers and BOM for the 64 x 64 sensor and its readout board (CERN-OHL-P-2.0)
docs/          the website (MkDocs Material; mkdocs.yml at the root, published by .github/workflows/pages.yml)
site_tools/    scripts that produce the website media and the Supplementary Videos (see site_tools/README.md)
```

## Demo

The demo package, `demo_2-24-2026_rat4.zip` (415 MB; 1.36 GB unzipped), is part of the data deposit on Zenodo, [doi:10.5281/zenodo.23286364](https://doi.org/10.5281/zenodo.23286364); the DOI resolves once the deposit is published. It holds one complete recording, rat 4 on 24 Feb 2026 (sciatic nerve pinch group, two weeks before surgery): an 85-s session with five runway crossings. It contains the raw pressure packets (1.0 GB), the overhead video (334 MB) and that recording's annotations, in the same layout as the full data deposit. Extracting it to `C:\` gives `C:\gait_demo\data`.

```matlab
setenv('GAIT_PYTHON', 'C:\path\to\python.exe')   % Python with PyTorch, if not on the PATH
addpath('<repo>/demo')
run_demo('C:\gait_demo\data', 'C:\gait_demo\work')
```

It runs s1 (background model), s2, s3 and s4 and writes to `work/demo_results/`:

- `walking_windows.csv`: the 5 walking windows
- `stance_events.csv`: the 58 labeled stance events (paw, start and end time, position)
- `labeled_walking_windows.mp4`: the overhead camera and pressure map of each walking window, every stance circled and labeled FL/FR/HL/HR (37 MB, about 0.25× real time)

The two tables are compared with `demo/expected/`; a successful run ends with `DEMO PASSED`. Typical run time is about 9 minutes on a desktop workstation (32 logical cores), with or without a GPU: about 6 minutes for the s2 contact detector and 2.5 minutes to render the video.

## Requirements

- **MATLAB** (tested on R2023b) with the Image Processing, Signal Processing, and Statistics and Machine Learning toolboxes.
- **Python 3** for the tail-base CNN: `pip install -r requirements.txt` (tested with Python 3.12, NumPy 2.4, OpenCV 4.13, PyTorch 2.12 CPU and 2.11 CUDA). Install time is a few minutes.
- **A GPU is not needed.** On the demo recording a CPU-only run took the same time and gave the same labeled stance events. Tail-base positions agreed on all but 1 of 1,376 frames, which changed the camera votes of 1 of 197 detector contacts and no label.
- **Disk:** about 60 MB of output per recording, two thirds of it tail-base frame images.
- **Recording only:** the readout boards and firmware (`acquisition/firmware/`), a computer with four USB ports and the overhead cameras, plus `pyserial` and `scipy`.

## Data

The recordings and the study annotations are on Zenodo, [doi:10.5281/zenodo.23286364](https://doi.org/10.5281/zenodo.23286364) (CC BY 4.0), as one zip per recording (`<M-D-YYYY>_ratN.zip`, 85 files, about 380 MB each) plus `annotations.zip`. Extract all of them into the same folder and point `GAIT_DATA_ROOT` at it:

```
<data_root>/
  <M-D-YYYY>/runway/ratN/runway_tactile_data_*.mat   raw pressure packets (+ camera frame timestamps)
  <M-D-YYYY>/runway/ratN/camera_*.mp4                 overhead video
  annotations/
    recordings.csv               the 85 analyzed recordings (paths relative to data_root)
    homographies/                camera -> sensor projective transform, one per recording
    blind_labels/                manual FL/FR/HL/HR labels (blinded to the algorithm)
    mobile_bout_windows.csv      manually selected walking windows
    cop_trajectory_corrections.csv   keep/trim decisions that produced those windows
    corrected_contacts.csv       manually reviewed contacts over whole recordings, including standing
    mass.csv                     body mass by rat and date
```

## Setup

Set these environment variables before starting MATLAB, or edit the top of `pipeline/gait_config.m`:

| Variable | Meaning |
|---|---|
| `GAIT_DATA_ROOT` | the downloaded data folder above |
| `GAIT_WORK_ROOT` | where outputs are written |
| `GAIT_PYTHON` | Python executable with PyTorch (default `python`) |
| `GAIT_ANNOTATIONS_ROOT` | optional; defaults to `<data_root>/annotations` |

Then add the code to the MATLAB path:

```matlab
addpath('<repo>/pipeline')
```

## Recording

`acquisition/record_runway.py` runs on the acquisition computer (macOS) with the four readout boards connected over USB serial. It sends each board its settings, then releases the board and camera threads from one shared start time, and saves `runway_tactile_data_<time>_M<M>_T<threshold>_D<digipot>.mat` plus one `camera_<K>_<time>.mp4` per camera. The paper's recordings used 90 s, M = 200, threshold 700, digital potentiometer 100, and two cameras at 1920 × 1080 (30 fps target; about 25-27 fps achieved, so use the saved per-frame timestamps). Edit the serial ports and camera indices at the bottom of the script. Each board streams about 880 frames per second; see `acquisition/firmware/README.md` for the sampling scheme and packet format. `live_view_runway.py` shows the live pressure map.

## Running the pipeline

Every stage takes an optional list of recordings (`output_name` values from `recordings.csv`) and skips work that already exists.

```matlab
[cfg, R] = gait_config();            % R = recording list with absolute paths
rec = R.output_name(R.rat == 6);     % e.g. one animal

s1_prepare_recordings("backgrounds", rec)  % background image of each overhead video
s2_detect_contacts(rec)                    % ~6 min per recording
s3_find_mobile_bouts("extract", rec)       % COP traces and candidate walking bouts
s4_label_paws(rec)                         % paw-labeled stance events in the walking windows
```

**s1, prepare recordings.** `"backgrounds"` builds the pixel-wise median background image of each overhead video listed in `recordings.csv`; s2 needs it. For a new recording set, `"pick"` chooses the overhead video for each tactile file, `"corners"` asks you to click the four visible platform corners in each video (the sensor corners are inferred from the platform template and a homography is saved), and `"background"` builds the background images and writes a new recording list to `work_root/setup/`.

**s2, detect contacts.** Overhead frames (30 fps) are background-subtracted, warped into the 256 × 64 board space with the body mask, and passed to the tail-base CNN. The detector then reconstructs the 64 × 256 pressure movie from the board packets, segments pressure contacts, and accumulates camera body-quadrant votes (FL/FR/HL/HR) for each contact. Output: `work_root/dynamics/<recording>/`.

**s3, walking bouts.** The whole-animal centre of pressure is computed at ~100 Hz, with each board rendered from its nearest packet by timestamp. Candidate walking bouts are proposed from its speed. `"correct"` opens a review window to keep, reject or trim each candidate; `"stats"` and `"export"` write the per-bout table and the walking windows. The paper used candidates reviewed by hand (the deposit's `mobile_bout_windows.csv`).

An improved automatic detector, `detect_walking_bouts` (actions `"review_auto"` / `"export_auto"`), is included but was **not** used in the paper. It proposes bouts for the same review window. On the 81 labeled recordings, 95% of the 2,469 manually labeled walking prints have their stance midpoint inside one of its proposed bouts. The proposals add time to review: about 1,000 s of proposed bouts against 619 s of manually selected walking windows.

**s4, paw labels.** Inside each walking window, stance contacts are re-segmented from the pressure movie. Each is assigned FL/FR/HL/HR from its position relative to the smoothed whole-animal COP and walking direction, plus 0.3 × log of the camera votes; left/right is decoded in onset order (Viterbi), and back-to-back pieces of one stance are merged. In the manually selected walking windows of 81 recordings, 2,303 of 2,469 manually labeled prints (93.3%) were found and given the correct paw. Output: `work_root/mobile_contacts/<recording>_mobile_contacts.mat`. With `s4_label_paws(rec, struct('video', true))` it also writes `<recording>_paw_labels.mp4`: camera and pressure map for each walking window, every stance labeled, and "human: XX" where a manual label exists and disagrees. These are the final paw labels; s2's provisional labels from camera votes are not used downstream.

**s5, grams.** `s5_calibrate_to_grams(pixel_sum, centroid_x)` converts a summed taxel response with the curve of the board the contact lies on (boards ordered 4-3-2-1 left to right). Values above the calibrated range (~410-421 g) return NaN. See `data/calibration_0_450/README.md`.

## Outputs

Everything is written under `GAIT_WORK_ROOT`. Conventions used by all stages:

- **Time:** seconds on the recording's shared clock, starting at the first pressure sample. Detector times, walking windows and stance events are all on this base.
- **Position:** taxel coordinates on the 64 × 256 runway. `centroid_x` is the column along the runway (1-256; boards 4, 3, 2, 1 from left to right) and `centroid_y` the row across it (1-64). One taxel is 2 mm; COP traces in s3 are already in mm.
- **Pressure:** raw readout counts (12-bit, 0-4095; larger values are readout glitches). Summed responses such as `dynamic_peak_total_pressure` are sums of counts. Convert sums to grams with `s5_calibrate_to_grams`.

| Stage | File (under `GAIT_WORK_ROOT`) | Contents |
|---|---|---|
| s1 | `background_models/<recording>_background_model.mat` | `bg_model`: 1080 × 1920 × 3 uint8 background image (rotated like the analysis frames); `frame_transform`, `source_video`, `n_background_frames` |
| s2 | `dynamics/<recording>/square_tailbase_predictions.csv` | one row per sampled camera frame (30 fps): `frame_index`, `time_s`, `tailbase_x_px`, `tailbase_y_px` (board coordinates, 0-255 × 0-63), `tailbase_confidence` |
| s2 | `dynamics/<recording>/<tactile file>_peak_seed_footstep_dynamics.mat` | the detector output, below |
| s3 | `cop_trajectory/cop_trajectory_raw.mat` | `raw_results`, one element per recording, below |
| s3 | `cop_trajectory/cop_tortuosity_by_bout.csv` | one row per candidate bout: `keep`, `trim_start_idx`/`trim_end_idx` (from the review), `duration_s`, `path_length_mm`, `displacement_mm`, `tortuosity`, `mean_speed_mm_s`, `net_speed_mm_s`, and the same for the video body centroid (`geom_centroid_*`) |
| s3 | `cop_trajectory/mobile_bout_windows.csv` | walking windows: `recording`, `bout_index`, `t_start`, `t_end` |
| s4 | `mobile_contacts/<recording>_mobile_contacts.mat` | `contacts` (the stance events), `bout_windows` (N × 2, s), `info`, below |
| s4 | `mobile_contacts/<recording>_paw_labels.mp4` | labeled video, with `struct('video', true)` |

**s2 detector output** (`*_peak_seed_footstep_dynamics.mat`):

- `pressure_movie_frames`: 64 × 256 × T uint16, the reconstructed pressure movie (about 120 frames per second).
- `pressure_movie_times`: T × 1, the time of each frame.
- `footstep_events`: the detector's contacts. Fields used downstream are:
  - `start_time`, `end_time`, `duration`, `start_frame`, `end_frame`
  - `centroid_x`, `centroid_y`
  - `quad_votes`: 1 × 4 camera body-quadrant votes for FL, FR, HL, HR
  - `label`: provisional, FL/FR/HL/HR or `noise`; superseded by s4
  - `valid_stance`
  - `dynamic_roi`: crop box `x1`, `x2`, `y1`, `y2`
  - `roi_frames`: the pressure crop over the stance
  - `dynamic_peak_total_pressure`
- `body_axis_trace`: the camera-derived body axis over time (`time`, body centroid `cx`, `cy`, unit vectors `head_ax_*` and `right_ax_*`, `reliable`).
- `clean_gait_events`, `export_params`, `export_source`: bookkeeping and the detector settings used.

**s3 COP trace** (`raw_results`): one element per recording, with:

- the recording's metadata
- `t` (s, ~100 Hz) and `source_t`
- `cop_x_mm`, `cop_y_mm`: smoothed whole-animal COP (`raw_cop_*` unsmoothed)
- `geom_centroid_*`: the unweighted centroid of the active taxels
- `total_pressure`, `n_active_px`, `velocity_mm_s`
- `is_moving`, `bout_starts`, `bout_ends`: candidate bouts, as indices into `t`

**s4 stance events** (`contacts`): one element per contact, sorted by start time. Use the ones with `mobile_valid = true`; contacts with `mobile_duplicate = true` are fragments of another stance. Per stance event:

| Field | Meaning |
|---|---|
| `label` | FL, FR, HL or HR (final) |
| `start_time`, `end_time`, `duration` | stance timing (s) |
| `start_frame`, `end_frame` | frame indices into `pressure_movie_frames` |
| `centroid_x`, `centroid_y` | contact position (taxels) |
| `dynamic_peak_total_pressure` | peak summed response during stance (counts) |
| `bout_index` | row of `bout_windows` the stance lies in |
| `mobile_margin` | assignment confidence: the smaller of the \|log-odds\| for left vs right and for fore vs hind (0 = coin flip) |
| `quad_votes` | camera votes borrowed from the nearest s2 contact |
| `track` | the frame-by-frame track behind the contact |

`demo/run_demo.m` shows how to turn the valid contacts into a simple table (`stance_events.csv`).

## License and citation

Code: MIT License; see [LICENSE](LICENSE). Hardware design files in `hardware/`: CERN-OHL-P-2.0; see [LICENSE-hardware](LICENSE-hardware). Website text, figures and media in `docs/`: CC BY 4.0; see [LICENSE-docs](LICENSE-docs). The recordings are released separately under CC BY 4.0.

If you use this code or data, please cite the paper (manuscript in preparation; see [CITATION.cff](CITATION.cff) and the [website](https://tactilearena.github.io/paper/)).

This repository started as [victorlu2220/Gait-Project-Pipeline](https://github.com/victorlu2220/Gait-Project-Pipeline); its history is preserved here.
