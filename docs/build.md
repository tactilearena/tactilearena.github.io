---
title: Build
description: What goes into a TactileArena runway, what it costs in parts, how it goes together, and how to flash, record and calibrate it.
---

# Build a TactileArena

<p class="ta-lede">One runway is four identical modules: a flex-circuit sensor, a piezoresistive film over it, and a
readout board under the edge. Everything else is a clear enclosure, a waterproof cover, an overhead camera and a
computer.</p>

<figure class="ta-media ta-media--contain" markdown>
![One sensor module: a 64 by 64 flex-PCB sensor with its readout board plugged into the tail.](assets/photos/module.png){ loading=lazy }
</figure>

## What you need { #parts }

| Part | Per runway | Notes |
|---|---|---|
| Sensor module (flex PCB, 2 layers, 157.9&nbsp;&times;&nbsp;179.7&nbsp;mm outline) | 4 | 64&nbsp;&times;&nbsp;64 electrode pairs at 2&nbsp;mm pitch; no components. Its two 70-contact tails plug straight into the readout board. Order as flex (FPC) with stiffeners on the tails. |
| Readout board (4-layer PCB, 92&nbsp;&times;&nbsp;56&nbsp;mm) | 4 | Teensy 4.1, 2&nbsp;&times; ADG732 32:1 multiplexers, 2&nbsp;&times; AD7476 12-bit ADCs, 8&nbsp;&times; 74LVC595 shift registers, op-amps, two 70-pin flex connectors (Molex 505110). |
| Piezoresistive film (Velostat/Linqstat) | ~4 pieces of 140&nbsp;&times;&nbsp;140&nbsp;mm | Lies over the electrode grid. |
| Waterproof cloth | ~1 yard | Covers the sensing surface; the animal walks on it. |
| Clear acrylic walls and floor, USB cables and hub, overhead camera(s), computer | | The recording script runs on macOS with two 1920&nbsp;&times;&nbsp;1080 cameras. |

## What it costs { #cost }

Parts for one four-module runway come to about **US$540** (range about US$480&ndash;690), or **about US$135 per
64&nbsp;&times;&nbsp;64 module**. That assumes you solder the boards yourself, order bare PCBs from any fab, and buy parts
at retail. Prices were checked in October 2026.

| | Per runway |
|---|---|
| Readout electronics (parts for 4 boards) | $308 |
| 4 &times; Teensy 4.1 | $126 |
| Readout PCBs and stencil (one order of 5) | ~$13 |
| Flex sensor PCBs (one order of 5) | ~$75 (estimate; $30&ndash;200 depending on fab) |
| Piezoresistive film and waterproof cloth | ~$15 |
| **Total** | **~$540** |

The two analog chips (ADG732 multiplexer and AD7476 ADC, two of each per board) are almost half the total. The flex
sensor is the least certain line: quote it with your fab before ordering. Shipping, tax, tools, the enclosure,
cameras and the computer are not included. Assembly by the board house is optional and adds roughly US$115.

!!! note "Design files"
    Fabrication files for the sensor module and the readout board (KiCad sources, Gerbers and the bill of
    materials) are being prepared for release here.

## Assembly { #assembly }

<div class="ta-story" markdown>
<div class="ta-story__text" markdown>

1. **Readout boards.** Solder the parts, with the Teensy 4.1 on headers. Flash the firmware (below) with a different
   board ID on each.
2. **Connect each sensor.** Push each sensor's flex tail into the two connectors of its readout board.
3. **Lay out the arrays.** Place the four sensors edge to edge so their taxel grids line up. The pipeline expects
   boards 4, 3, 2, 1 from left to right along the runway.
4. **Add the film.** Cover the electrode grids with piezoresistive film.
5. **Cover and enclose.** Lay the waterproof cloth flat over the film and set the clear walls around it. Mount the
   overhead camera so it sees the whole floor.
6. **Connect and check.** Plug the four boards into the computer, run `live_view_runway.py` and check that every
   board's LED lights up and that pressing the floor shows up in the right place.

The video (93&nbsp;s) shows steps 2&ndash;6.

</div>
<figure class="ta-media" markdown style="max-width:22rem">
<video controls preload="none" playsinline data-poster="assets/video/assembly.jpg" aria-label="Assembly video: connecting sensors to readout boards, aligning four arrays, covering with piezoresistive film, connecting to the computer">
  <source src="assets/video/assembly.mp4" type="video/mp4">
  <track kind="chapters" src="assets/video/assembly_chapters.vtt" srclang="en" label="Steps">
</video>
</figure>
</div>

## Flash the firmware { #firmware }

The firmware is in [`acquisition/firmware/`](https://github.com/tactilearena/tactilearena.github.io/tree/main/acquisition/firmware)
(Arduino IDE with Teensyduino and the `MCP41HVX1` digital-potentiometer library).

- **Set `BOARD_ID` (line 5) to 1, 2, 3 or 4 before flashing each board.** The ID is sent in every packet.
- On power-up a board waits for one line, `M threshold digipot`, from the host, sets its gain, replies `OK` and
  starts streaming. It runs the [adaptive sampling loop](how-it-works.md#sampling): every frame is a header
  (`0xDEADBEEF`, board ID, pixel count, frame counter) followed by (index, value) pairs.

## Record { #record }

`acquisition/record_runway.py` configures the four boards, starts them and the cameras from one shared start time,
and saves `runway_tactile_data_<time>_M<M>_T<threshold>_D<digipot>.mat` plus one MP4 per camera with per-frame
timestamps. Edit the serial ports and camera indices at the bottom of the script. The paper's recordings used
90&nbsp;s, M&nbsp;=&nbsp;200, threshold 700 and digital potentiometer 100, with cameras at 1920&nbsp;&times;&nbsp;1080 (30&nbsp;fps
target; about 25&ndash;27&nbsp;fps achieved, which is why the per-frame timestamps matter).

```bash
pip install pyserial scipy numpy opencv-python
python acquisition/live_view_runway.py     # live pressure map, nothing saved
python acquisition/record_runway.py        # one synchronized recording
```

## Calibrate { #calibrate }

Calibration curves for the paper's four boards are in
[`data/calibration_0_450/`](https://github.com/tactilearena/tactilearena.github.io/tree/main/data/calibration_0_450).
They belong to those boards. A new build needs its own: press each module through the same cover onto a
reference force plate (the paper used three 5&nbsp;kg load cells and an NAU7802 24-bit amplifier on a Teensy),
then fit summed taxel response to load as described in that folder's README.
