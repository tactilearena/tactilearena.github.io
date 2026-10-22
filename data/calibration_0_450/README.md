# Board calibration, 0-450 g

`calibration_0_450.json` maps a summed taxel response (pixel sum) to mass-equivalent load in grams, separately for each of the four boards. `pipeline/s5_calibrate_to_grams.m` applies it.

## How the curves were made

- **Source.** Each board was pressed by a finger on a reference force plate, through the same waterproof cover used in the animal experiments.
- **Data cleaning.** The first 3 s of each recording were dropped (start-up transient). Taxel values above 4,095 were set to zero before summing each frame, and the frame sums were interpolated to the force-plate timestamps. The force reference was tared with the median of its values below the 20th percentile.
- **Calibration points.** Samples with 0-450 g reference load were sorted by load and split into 20 groups of about equal size; the median pixel sum and median load of each group form one point. A zero-load point comes from samples between -3 and 3 g. The points were made monotonic and duplicate pixel sums removed, which leaves 17-19 points per board.
- **Interpolation.** Pixel sums are converted with monotone piecewise cubic Hermite interpolation (PCHIP) between those points.
- **Range.** Values below the first point return 0 g. Values above the last point (about 410-421 g, depending on the board) are outside the calibrated range and return NaN.

In the JSON, `boards.<boardN>.pixel_sum_knots` and `force_g_knots` are the paired calibration points. The remaining fields
record the fit: `rmse_g`, `mae_g` and `n_samples` are the in-sample errors and sample count of the final curve (the
held-out errors are given under Accuracy), `presses_used` lists the presses retained for that board, numbered in
recording order (`all` for board 1), and `force_tare_g` and `baseline_sum` are the force and taxel-sum offsets.

## Accuracy

Accuracy was evaluated by leaving out one press at a time. The RMSE of estimated against reference load, over held-out samples between 0 and 450 g, was 23.4, 30.6, 25.9 and 27.2 g for boards 1-4.

## Notes on use

- **Relative error.** The absolute error is roughly constant across the range, so the relative error is lowest for loads of about 50-300 g.
- **Use each board's own curve.** Sensitivity differs between boards by up to about 1.5× at low load.
- **Board 2** has the largest held-out error (30.6 g).
- **Not validated for transfer.** The curves were not tested on other sessions, other contact geometries (finger vs paw) or other positions on a board.
- **Board-specific.** The curves apply to the four boards used in the study; other sensors require their own calibration against a reference force plate, following the procedure above.
