# Readout-board firmware

`readout_64x64/readout_64x64.ino` is the firmware for the four 64 × 64 readout boards (Teensy 4.1; Arduino IDE with Teensyduino and the `MCP41HVX1` digital-potentiometer library).

**Before flashing each board, set `BOARD_ID` (line 5) to 1, 2, 3 or 4.** The ID is sent in every packet. The recording script names boards by USB port: in the paper's recordings `Board1`-`Board4` carried IDs 4, 3, 2, 1. The pipeline's runway layout (boards 4-3-2-1 left to right) assumes that order, so connect the ports the same way.

What the firmware does:

- **Configuration.** On power-up it waits for one line `M threshold digipot` from the host (sent by `acquisition/record_runway.py`), sets both digital potentiometers and replies `OK`. A new line during streaming changes the settings.
- **Adaptive sampling, up to M taxels per frame.** It first re-reads up to 50 taxels that triggered neighbourhood sampling in the previous frame. It then follows a fixed coarse-to-fine sampling pattern, shifted by one column each frame. Whenever a reading exceeds the threshold, it also reads that taxel's 3 × 3 neighbourhood, recursively. ADCs are read over SPI at 6 MHz.
- **Streaming.** Every sampled taxel is sent, including those below the threshold: the threshold steers where the board looks, not what it sends. Each frame is the header `0xDEADBEEF`, board ID (uint16), pixel count (uint16) and frame counter (lower 16 bits), followed by `count` (index, value) uint16 pairs. Index `0xFFFF` ends a frame (its value is the lower 16 bits of the frame's sampling time in microseconds) and `0xFFFE` acknowledges a configuration change. Index = `row*32 + col` for columns 0-31 and `row*32 + (col-32) + 2048` for columns 32-63.

In the paper's recordings (M = 200, threshold 700, digipot 100) every board streamed frames at approximately 1 kHz (median interval about 1 ms), with essentially every frame holding exactly M = 200 taxels.
