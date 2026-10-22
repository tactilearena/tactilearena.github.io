# TactileArena overview: narration script

Timed to overview.mp4; the on-screen captions carry the same text.

- **00:01** We turned the ground into a sensor.
- **00:15** Viewed from above, the paws of a walking rat are largely hidden beneath its body.
- **00:20** The tactile floor records each contact: its location, its duration and the load it bears.
- **00:24** Labels indicate automatic paw assignments (FL, FR, HL, HR).
- **00:27** Four 64 × 64 sensor modules form a 512 × 128 mm runway of 16,384 taxels at 2-mm pitch.
- **00:32** Each module is a flexible electrode array beneath a piezoresistive film, read by a dedicated Teensy-based board.
- **00:37** Assembly: each sensor module is connected to its readout board through its two flexible tails.
- **00:43** Rather than scanning every taxel, each board measures 200 of its 4,096 taxels per frame.
- **00:47** Active contacts are tracked, a coarse-to-fine scan monitors the module, and loaded regions are resolved at full density.
- **00:54** Recorded acquisition frames: paw contacts are resolved completely, while unloaded regions are sampled sparsely.
- **00:59** Adaptive sampling enables acquisition across 16,384 taxels at approximately 1,000 frames per second.
- **01:05** With synchronized video, contacts are assigned to individual paws, correctly identifying 93.3% of 2,469 manually annotated contacts.
- **01:11** The load on each paw is then resolved at approximately 1 kHz throughout every stance.
- **01:19** After sciatic nerve pinch, rats continued to place the injured hindpaw on the ground.
- **01:23** The loading ratio, however, decreased by approximately 60%, nearly twice the decrease in the duty-factor ratio.
- **01:27** In three injured and two sham-operated rats followed for two weeks, both ratios decreased and then returned toward baseline.
- **01:30** Peak loading of the injured hindpaw decreased by 27%, and that of the contralateral hindpaw increased by 22–23%.
- **01:34** Contact morphology also changed: injured-hindpaw contacts became smaller and more elongated (cyan outlines).
- **01:41** The modular design allows the same four modules to form other arenas, such as a square open field with three rats.
- **01:46** Future applications include integration with pose estimation, neural recordings, contact-triggered perturbations and shear sensing.
- **01:51** Open resources: hardware design files, firmware, analysis software and 85 recordings. tactilearena.github.io
