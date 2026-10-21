---
title: How it works
description: The TactileArena sensing surface, adaptive compressive sampling at approximately 1 kHz, force calibration, and the fusion of pressure and video into paw-resolved measurements.
---

# How it works

<p class="ta-lede">TactileArena measures contact directly. The floor operates as a pressure-imaging sensor, sampled
fast enough to resolve load dynamics within individual steps and recorded on the same clock as overhead video.</p>

## Sensing surface { #surface }

<div class="ta-story" markdown>
<div class="ta-story__text" markdown>

Each **module** is a flexible printed circuit carrying a 64&nbsp;&times;&nbsp;64 array of electrode pairs at
2-mm pitch: 4,096 tactile pixels (taxels) over 128&nbsp;&times;&nbsp;128&nbsp;mm. A piezoresistive film covers the
array, and applied pressure reduces its resistance between the underlying electrodes. A waterproof cloth covers the
assembly, so that the animal does not contact the electronics.

Each module is read by a dedicated **readout board** (a Teensy 4.1 microcontroller with analog multiplexers and
analog-to-digital converters) connected directly to the module's flexible tails. Four modules placed side by side
form the 64&nbsp;&times;&nbsp;256-taxel runway: 16,384 taxels over 512&nbsp;&times;&nbsp;128&nbsp;mm, enclosed by
transparent walls beneath an overhead camera.

Because each module is read independently, the modules can be arranged in other geometries, such as a square
open-field arena ([Modularity](index.md#beyond); Supplementary Video 5 on the [Paper](paper.md#videos) page).

</div>
<figure class="ta-fig" markdown>
![Schematic of the runway: overhead camera, acrylic walls, waterproof cloth over the pressure-sensor sheet and piezoresistive layer; photograph of the sensor array with its readout board.](assets/figures/overview.jpg){ loading=lazy }
<figcaption><strong>Runway configuration.</strong> An overhead camera above a 64&nbsp;&times;&nbsp;256-taxel pressure-sensor sheet (four modules) beneath a waterproof cloth. Panel b shows one module with its readout board. Adapted from the manuscript.</figcaption>
</figure>
</div>

<div class="ta-cards" markdown>
<figure class="ta-card" markdown>
![The assembled runway: an acrylic base with four readout boards along one side, acrylic walls and a cloth-covered sensing floor.](assets/photos/runway_assembled.jpg){ loading=lazy }
<figcaption>Assembled runway: four modules beneath the cloth between the walls, with the four readout boards along one side (a toy mouse is shown for scale).</figcaption>
</figure>
<figure class="ta-card" markdown>
<div class="ta-media" markdown>![A readout board: Teensy 4.1, eight shift registers, two multiplexers, two analog-to-digital converters and two flexible-circuit connectors holding the sensor tails.](assets/photos/readout_64x64.jpg){ loading=lazy }</div>
<figcaption>Readout board: a Teensy 4.1, shift registers that drive the rows, multiplexers and analog-to-digital converters that read the columns, and two connectors for the sensor tails.</figcaption>
</figure>
<figure class="ta-card" markdown>
<div class="ta-media ta-media--contain" markdown>![Four sensor modules tiled two by two with their four readout boards.](assets/photos/modules_2x2.png){ loading=lazy }</div>
<figcaption>Four modules tiled in a 2&nbsp;&times;&nbsp;2 configuration.</figcaption>
</figure>
</div>

## Adaptive compressive sampling { #sampling }

In a conventional raster-scanned pressure array, every taxel is measured in each frame, so that increasing the
sensing area or density reduces the frame rate. During locomotion, however, only a small fraction of the surface is
loaded at any moment. The readout firmware therefore concentrates its measurements on active contacts (adaptive
compressive sampling; [Slepyan et al., 2024](https://arxiv.org/abs/2410.13847)).

In each frame, every board measures a fixed budget of **M taxels** (M&nbsp;=&nbsp;200, 4.9% of the module, in the
study recordings) in the following order:

1. **Tracking of active contacts.** Taxels that triggered neighbourhood sampling in the previous frame are measured first.
2. **Background scan.** The remaining budget follows a fixed coarse-to-fine pattern that begins at the module centre
   and continues through grids of successively halved pitch (32, 16, 8, 4 and 2 taxels), so that an incomplete scan
   still covers the module uniformly. The pattern shifts by one column each frame, and by one row after each full
   sweep of columns, so that every taxel is measured across successive frames.
3. **Neighbourhood expansion.** Whenever a reading exceeds the threshold T, the unmeasured taxels in its
   3&nbsp;&times;&nbsp;3 neighbourhood are measured, recursively, so that each contact is captured at full resolution
   together with a boundary of unloaded taxels.

Each taxel is measured at most once per frame, and all measurements, including those below threshold, are transmitted
to the host computer. In the study recordings (M&nbsp;=&nbsp;200, T&nbsp;=&nbsp;700 ADC counts), each board produced
a frame approximately every millisecond.

### Interactive simulation { #simulator }

The left panel shows the pressure applied to one module by a simulated paw that follows the pointer (press and drag;
in the absence of input, two simulated paws traverse the module). The right panel shows the taxels measured by the
firmware's sampling loop in the current frame.

<div class="ta-widget" id="ta-sim" data-src="../assets/data/">
  <div class="ta-sim-grid">
    <figure><canvas data-view="true" aria-label="Simulated pressure applied to one 64 by 64 module"></canvas><figcaption>Applied pressure</figcaption></figure>
    <figure><canvas data-view="read" aria-label="Taxels measured by the firmware in the current frame"></canvas><figcaption>Taxels measured in the current frame</figcaption></figure>
  </div>
  <div class="ta-widget__row">
    <span class="ta-widget__stats">Loading&hellip;</span>
  </div>
  <div class="ta-widget__row">
    <label>Budget M <input type="range" name="M" min="40" max="1200" step="10" value="200"><output name="M">200</output></label>
    <label>Threshold T <input type="range" name="thr" min="200" max="2500" step="50" value="700"><output name="thr">700</output></label>
    <button type="button" data-act="play" aria-pressed="false">Pause</button>
  </div>
  <div class="ta-widget__legend">
    <span><span class="ta-swatch" style="background:#0b080f;border:1px solid #333"></span>not measured in this frame</span>
    <span><span class="ta-swatch" style="background:#464a5e"></span>measured, below threshold</span>
    <span><span class="ta-swatch" style="background:linear-gradient(90deg,#57106e,#bc3754,#f98e09,#fcffa4)"></span>measured, above threshold</span>
  </div>
</div>

Reducing **M** makes the background scan sparser while contacts remain fully resolved; increasing **T** restricts
neighbourhood expansion to more strongly loaded regions. The simulation is displayed at approximately 30 frames per
second; the readout boards operate at approximately 1,000.

### Recorded acquisition frames { #replay }

The display below reproduces the recorded data: for each of the four boards, the taxels measured in its most recent
frame during 0.6&nbsp;s of walking (rat 4, 24 February 2026, before surgery).

<div class="ta-widget" id="ta-replay" data-src="../assets/data/">
  <canvas aria-label="The four runway modules: taxels measured by each board in its most recent frame, from recorded data"></canvas>
  <div class="ta-widget__row">
    <button type="button" data-act="play" aria-pressed="false">Play</button>
    <button type="button" data-act="step">Next frame</button>
    <label>Speed <select name="speed">
      <option value="0.01">1/100&times;</option>
      <option value="0.04" selected>1/25&times;</option>
      <option value="0.25">1/4&times;</option>
    </select></label>
    <label><input type="checkbox" name="showread" checked> show taxels measured below threshold</label>
  </div>
  <div class="ta-widget__row"><span class="ta-widget__stats">Loading&hellip;</span></div>
</div>

Modules without active contacts allocate their full budget to the background scan, which therefore reaches a finer
grid level in those modules.

<script src="../javascripts/sampling.js"></script>

### Configurable acquisition { #budget }

M and T are transmitted to each board at the start of a recording, so that the balance between frame rate and
background coverage is set in software. A smaller M yields a higher frame rate with sparser background coverage per
frame, and a larger M the converse. The threshold defines the minimum load treated as contact, and a programmable
amplifier gain (digital potentiometer) sets sensitivity for the expected loading range. The nominal 1-kHz frame rate
is therefore a property of the configuration used in the study.

## Force calibration { #calibration }

<div class="ta-story ta-story--flip" markdown>
<div class="ta-story__text" markdown>

Raw taxel responses are converted to load using board-specific calibration curves. Each module was loaded through
the same waterproof cover on an independent force plate (three load cells with a 24-bit amplifier). The summed
tactile response followed the loading and unloading phases of the force-plate signal (RMSE 0.101 between
independently normalized signals). Piecewise cubic Hermite curves, one per board, map summed responses to
mass-equivalent load between 0 and approximately 410&ndash;421&nbsp;g.

On presses withheld from the fit, the curves predicted load with RMSE of 23.4&ndash;30.6&nbsp;g, approximately
5&ndash;8% of the body mass of the rats studied. The nerve-injury analyses normalize loading by body mass and
compare each animal with its own presurgical baseline.

</div>
<figure class="ta-fig" markdown>
![Calibration setup, pressure-map snapshots during a press, force-plate and tactile signals, per-board calibration curves and held-out-press performance.](assets/figures/figS1_characterization.jpg){ loading=lazy }
<figcaption><strong>Characterization.</strong> Tactile and force-plate responses, per-board calibration curves (d) and held-out-press predictions (e). Supplementary Fig. S1 of the manuscript.</figcaption>
</figure>
</div>

## Analysis pipeline { #pipeline }

<figure class="ta-fig" markdown>
![Pipeline: high-speed pressure frames and overhead video; a convolutional network localizes the tail base; registration fuses video and pressure; contacts are assigned to paws and linked into footsteps.](assets/figures/fig1_workflow.jpg){ loading=lazy }
<figcaption><strong>Analysis pipeline</strong> (Fig. 1 of the manuscript). A1, pressure frame as acquired; black taxels were not measured in that frame. A2, overhead video. B, tail-base localization. C, registered fusion. D, paw assignment. E, footstep extraction.</figcaption>
</figure>

1. **Synchronization.** Pressure packets from the four boards and frames from the overhead cameras are timestamped
   against a common host clock from a shared start signal.
2. **Pressure frames.** The most recent packet from each board is reconstructed into a 64&nbsp;&times;&nbsp;64 image
   (taxels not measured in that frame were below threshold in recent frames and are set to zero), and the four images
   are combined into the 64&nbsp;&times;&nbsp;256 runway map.
3. **Registration.** A projective transform, defined from the platform corners in each recording, maps video frames
   onto the taxel grid; background subtraction yields the body mask.
4. **Body orientation.** A convolutional encoder&ndash;decoder localizes the tail base from the image and body mask;
   the vector from the tail base to the body centroid defines body orientation.
5. **Paw assignment.** Pressure contacts are tracked across frames, segmented into stance events, and scored for each
   paw according to their position relative to the smoothed whole-animal centre of pressure and walking direction.
   Camera-derived votes contribute a weighted term, and Viterbi decoding enforces consistent left/right sequences.

Within manually selected walking windows from 81 recordings, the pipeline correctly identified **2,303 of 2,469**
manually annotated contacts (93.3%; 95.7% of matched contacts). Walking-window selection and camera-to-sensor
registration are performed manually.

<figure class="ta-fig" markdown>
![Tail-base network architecture, training curves, localization accuracy, paw-assignment confusion matrix and examples.](assets/figures/figS2_decoder.jpg){ loading=lazy }
<figcaption><strong>Tail-base localization and paw-assignment accuracy</strong> (Supplementary Fig. S2). Panel d shows the confusion matrix for all 2,469 manually annotated contacts.</figcaption>
</figure>

### Measures computed for each contact { #measures }

| Measure | Definition |
|---|---|
| Stance, stride and duty factor | contact onset and lift-off of each paw; duty factor = stance duration / stride duration |
| Contact area and shape | area of the thresholded footprint (4&nbsp;mm² per taxel) and length-to-width ratio |
| Peak and time-integrated load | summed response per contact, calibrated to mass-equivalent grams, and its integral over stance |
| Centre of pressure (COP) | pressure-weighted centroid for the whole animal or within an individual paw |
| Interlimb ratios and imbalance | left-to-right hindpaw duty-factor and loading ratios; (L&minus;R)/(L+R) during hindpaw-only support |

The [Software](software.md) page describes how to run the pipeline; all parameters are given in the Methods of the
manuscript.

## Limitations { #limits }

- The piezoresistive film measures normal pressure; tangential (shear) forces are not measured.
- Calibration was performed per board on summed responses rather than per taxel; held-out errors were 23.4&ndash;30.6&nbsp;g.
- The 2-mm pitch resolves the plantar contact geometry of the rat paw; smaller animals would require finer-pitch sensors.
- Automated paw assignment was validated within walking bouts; turning, overlapping contacts and prolonged spontaneous behaviour require further validation.
