# TactileArena hardware

Design files for one TactileArena module: a 64 × 64-taxel flexible-PCB sensor and its readout board. A runway uses
four of each (16,384 taxels, 512 × 128 mm). Licensed under the
[CERN Open Hardware Licence v2, Permissive](../LICENSE-hardware) (CERN-OHL-P-2.0).

| Folder | Contents |
|---|---|
| [`sensor_64x64/`](sensor_64x64) | KiCad layout (`MD_sensor_64x64.kicad_pcb`; layout only, no components) and the Gerbers used for fabrication (`gerbers/MD_sensor_64x64_gerbers.zip`) |
| [`readout_64x64/`](readout_64x64) | KiCad schematic and layout (`readout_64x64_regulated.*`), Gerbers and drill files (`gerbers/readout_64x64_regulated_gerbers.zip`), JLCPCB assembly files ([`jlcpcb/`](readout_64x64/jlcpcb): BOM and placement) and the bill of materials ([`bom.csv`](readout_64x64/bom.csv)) |

The sensor Gerber zip is the file the sensors were made from; its copper layers and board outline match the KiCad
layout (checked layer by layer). The readout-board Gerbers and assembly files are exported from the KiCad layout
in this folder with the Fabrication Toolkit plugin (KiCad 10).

## Sensor module (`sensor_64x64`)

- **What it is:** a 64 × 64 grid of electrode pairs at 2 mm pitch (128 × 128 mm active area) with
  row and column traces routed to two 70-contact, 0.5 mm-pitch tails. There are no components on it. A
  piezoresistive film (Velostat/Linqstat) laid over the grid makes each electrode pair a pressure-sensitive taxel.
- **Fabrication:** 2-layer flexible PCB (FPC). The board setup in KiCad retains the default FR4 stackup, which does not apply.
- **Outline:** 157.9 × 179.7 mm (chamfered body plus the two tails). Traces are 0.2 mm; most vias are 0.4 mm pad /
  0.2 mm drill.
- **Tails:** each tail connects to one Molex 505110 connector on the readout board. A stiffener under the tail
  contacts should bring their thickness to the value specified for the connector (Molex 505110 datasheet).

## Readout board (`readout_64x64`)

- **What it does:** shift registers (74LVC595) drive the 64 rows, two 32:1 multiplexers (ADG732) select a column in
  each half of the sensor, and two 12-bit ADCs (AD7476) read them over SPI. Two digital potentiometers
  (MCP41HV51) set the gain. A Teensy 4.1 runs the [adaptive sampling firmware](../acquisition/firmware) and
  streams to the computer over USB.
- **PCB:** 4 layers, 1.6 mm, 91.9 × 56.3 mm, all parts on the top side. The smallest vias are 0.35 mm pad /
  0.15 mm drill; these should be confirmed against the capabilities of the fabrication service.
- **Parts:** [`bom.csv`](readout_64x64/bom.csv), per board. All parts except the Teensy 4.1 can be placed by the
  board house; [`jlcpcb/`](readout_64x64/jlcpcb) contains the JLCPCB BOM and placement files. The Teensy 4.1 is
  marked do-not-populate and is soldered by hand. Parts that are out of stock at JLCPCB when ordering can be sourced
  through its parts pre-order or global sourcing services, or soldered by hand.
- **Soldering:** the multiplexers (TQFP-48), shift registers (TSSOP-16) and the two 70-pin connectors are 0.5–0.65 mm
  pitch; a solder-paste stencil with a hot plate or reflow oven is recommended. The Teensy is mounted on 2 × 24 pin
  headers.
- **3D models** are not included; some footprints reference local model files, so these parts appear without bodies
  in the KiCad 3D viewer.

## Building a runway

A runway requires four sensor modules, four readout boards, piezoresistive film, a waterproof cloth and an enclosure.
The [Build guide](https://tactilearena.github.io/build/) describes the parts cost (approximately US$550 per runway),
the assembly procedure and video, firmware installation (`BOARD_ID` 1–4) and recording.
