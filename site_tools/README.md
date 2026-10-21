# Website and video tools

These scripts produce the website's figures, loops and videos (`docs/assets/`) and the Supplementary Videos. They
are not needed to run the analysis pipeline.

## Requirements

Python 3 with NumPy, SciPy, Pillow and Matplotlib; `ffmpeg` (version 5 or later) and `pdftoppm` (Poppler). The
IBM Plex Sans and IBM Plex Mono fonts are expected in `<TA_WORK>/fonts/` (`IBMPlexSans-VF.ttf`,
`IBMPlexMono-Regular.ttf`).

## Folders

| Variable | Default | Contents |
|---|---|---|
| `TA_WORK` | `.work/` in the repository (not tracked) | fonts, recording caches built by `ta_extract.py`, intermediate files and the full-quality Supplementary Videos |
| `TA_SOURCES` | `<TA_WORK>/sources` | source media that are not part of the data deposit (below) |
| `TA_PAPER_FIGS` | `<TA_SOURCES>/manuscript_figures` | manuscript figure PDFs |

Source media in `TA_SOURCES`:

| File | Used for |
|---|---|
| `figure_deck.pptx`, `poster_ner2025.pptx` | photographs of the sensor module, readout board, 2 × 2 tiling and assembled runway |
| `assembly.mp4` | Supplementary Video 1 |
| `annotated_pre_surgery.mp4`, `annotated_post_surgery.mp4` | Supplementary Videos 2 and 3 (annotated videos written by `s4_label_paws`) |
| `arena_three_rats.mov` | three rats on the open-field arena (home page, overview video, Supplementary Video 5) |

The pressure displays use the demonstration recording of the data deposit (rat 4, 24 February 2026, runway).
Supplementary Video 5 also uses the square-arena recording of the same session.

## Scripts

| Script | Output |
|---|---|
| `ta_extract.py` | compact cache of a recording's packets (`.npz`) |
| `ta_frames.py`, `ta_square.py` | pressure frames of the runway and of the square arena, reconstructed as in the pipeline |
| `ta_register.py`, `ta_selfcal.py` | camera-to-sensor registration |
| `ta_scene.py`, `media_common.py` | shared rendering: sessions, taxel drawing, colours and fonts |
| `make_hero.py`, `make_camera_floor.py`, `make_sampling.py` | the website's video loops |
| `export_sampling.py` | data for the interactive sampling displays (`docs/assets/data/`) |
| `make_site_assets.py` | photographs, manuscript figures, home-page card images and the arena clip |
| `make_overview.py` | overview video, its captions and `overview_narration.md` |
| `clean_assembly_video.py` | Supplementary Video 1 |
| `clean_annotated_videos.py` | Supplementary Videos 2 and 3 |
| `make_supp_sampling.py`, `make_supp_square.py` | Supplementary Videos 4 and 5 |

Usage is given at the top of each script.
