# TactileArena overview: narration script

Timed to overview.mp4; the on-screen captions carry the same text.

- **00:01** We turned the ground into a sensor.
- **00:15** From above, a walking rat hides its paws under its body.
- **00:20** The floor sees each one: where it lands, how long it stays down, and how hard it presses.
- **00:24** Labels are automatic paw identities: left/right, fore/hind (FL, FR, HL, HR).
- **00:27** Four 64 × 64 sensor modules make a 512 × 128 mm runway: 16,384 taxels at 2 mm pitch.
- **00:32** Each module is a flex circuit of electrodes under a piezoresistive film, read by its own Teensy-based board.
- **00:37** Plug each sensor into its board, line the four up, cover with film and a waterproof cloth.
- **00:43** Reading 16,384 taxels one by one would be slow. Each board reads only 200 per frame.
- **00:47** It follows last frame's contacts, scans the module coarse-to-fine, and reads every neighbour of anything pressed.
- **00:54** The real boards, frame by frame: each paw is read in full, the empty floor only sparsely.
- **00:59** That is how 16,384 taxels run at about 1,000 frames per second.
- **01:05** With video on the same clock, each contact is assigned to a paw: 93.3% of 2,469 hand-labelled contacts were correct.
- **01:11** Every paw's load is then measured about 1,000 times per second, through every step.
- **01:19** After a sciatic nerve pinch, rats kept stepping on the injured hind paw...
- **01:23** ...but its share of the load fell by about 60%, nearly twice the drop in its share of stance time.
- **01:27** Three injured and two sham rats over two weeks: both ratios fell, then recovered toward baseline.
- **01:30** The injured paw's peak load dropped 27%; the opposite hind paw took up 18–21% more.
- **01:34** Contact shape changed too: the injured paw's print became smaller and more elongated (blue boxes).
- **01:41** Because the floor is modular, the same four modules tile other arenas: here, three rats in a square open field.
- **01:46** Possible next steps: pose tracking, neural recordings, contact-triggered experiments, shear sensing.
- **01:51** Open: hardware design files, firmware, analysis code and 85 recordings. tactilearena.github.io
