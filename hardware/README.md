# TactileArena hardware

Design files for one TactileArena module: a 64 × 64-taxel flex-PCB sensor and the readout board that plugs into
it. A runway uses four of each (16,384 taxels, 512 × 128 mm). Licensed under the
[CERN Open Hardware Licence v2, Permissive](../LICENSE-hardware) (CERN-OHL-P-2.0).

| Folder | Contents |
|---|---|
| [`sensor_64x64/`](sensor_64x64) | KiCad layout (`MD_sensor_64x64.kicad_pcb`; layout only, no components) and the Gerbers used for fabrication (`gerbers/MD_sensor_64x64_gerbers.zip`) |
| [`readout_64x64/`](readout_64x64) | KiCad schematic and layout (`readout_64x64_regulated.*`), the Gerbers used for fabrication (`gerbers/readout_64x64_regulated_gerbers.zip`) and the bill of materials ([`bom.csv`](readout_64x64/bom.csv)) |

The Gerber zips are the files the boards were made from. Their copper layers and board outlines match the KiCad
layouts in this folder (checked layer by layer).

## Sensor module (`sensor_64x64`)

- **What it is:** a 64 × 64 grid of electrode pairs at 2 mm pitch (128 × 128 mm active area) with
  row and column traces routed to two 70-contact, 0.5 mm-pitch tails. There are no components on it. A
  piezoresistive film (Velostat/Linqstat) laid over the grid makes each electrode pair a pressure-sensitive taxel.
- **Order it as a 2-layer flexible PCB (FPC).** The KiCad board setup shows the default FR4 stackup; ignore it.
- **Outline:** 157.9 × 179.7 mm (chamfered body plus the two tails). Traces are 0.2 mm; most vias are 0.4 mm pad /
  0.2 mm drill.
- **Tails:** each tail plugs into one Molex 505110 connector on the readout board. Order a stiffener under the tail
  contacts so their thickness matches what the connector takes (see the Molex 505110 datasheet).

## Readout board (`readout_64x64`)

- **What it does:** shift registers (74LVC595) drive the 64 rows, two 32:1 multiplexers (ADG732) select a column in
  each half of the sensor, and two 12-bit ADCs (AD7476) read them over SPI. Two digital potentiometers
  (MCP41HV51) set the gain. A Teensy 4.1 runs the [adaptive sampling firmware](../acquisition/firmware) and
  streams to the computer over USB.
- **PCB:** 4 layers, 1.6 mm, 91.9 × 56.3 mm, all parts on the top side. The smallest vias are 0.35 mm pad /
  0.15 mm drill, so check your fab's capability.
- **Parts:** [`bom.csv`](readout_64x64/bom.csv), per board. The Teensy 4.1 and the two digital potentiometers
  (MCP41HV51) are marked do-not-populate in the schematic only because they were not in the board-house assembly
  order (JLCPCB did not stock the potentiometer at the time). Both are required: buy them separately and solder
  them by hand.
- **Soldering:** the multiplexers (TQFP-48), shift registers (TSSOP-16) and the two 70-pin connectors are 0.5–0.65 mm
  pitch. A solder-paste stencil and a hot plate or reflow oven make this much easier. The Teensy goes on 2 × 24 pin
  headers.
- **3D models** are not included; some footprints point to model files that only existed on our computers, so
  KiCad's 3D viewer will show those parts without bodies.

## Building a runway

You need four sensors, four readout boards, piezoresistive film, a waterproof cloth and an enclosure. The
[Build page](https://tactilearena.github.io/build/) has the parts cost (about US$550 in parts per runway), the
assembly steps and video, and how to flash the firmware (set `BOARD_ID` 1–4) and record.
