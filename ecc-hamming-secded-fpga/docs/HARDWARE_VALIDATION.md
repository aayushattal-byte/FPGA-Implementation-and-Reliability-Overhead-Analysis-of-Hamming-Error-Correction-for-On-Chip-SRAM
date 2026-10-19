# Hardware validation

**Status: not yet performed.** This page is the procedure and the place to record real results. Nothing below is filled in
until it has been measured on the board.

## Procedure
1. Program the bitstream; confirm `led[3]` (heartbeat) blinks.
2. `btn[0]` (step): expect `led[0]` PASS. Repeat 5 times.
3. Set `sw[6:0]` to a bit position 0..71, press `btn[1]` (inject): expect `led[1]` SEC.
4. Repeat step 3 for at least 10 different positions, including 0, 1, 2, 3, 4 (parity-bit positions), 71.
5. Press `btn[0]`, then inject two different bits: expect `led[2]` DED.
6. Optional: a third inject on the same word and record what the LEDs show (expected: SEC, wrongly).

## Results (fill in)

| Check | Expected | Observed | Photo/video |
|---|---|---|---|
| heartbeat | blinks | | |
| step | PASS | | |
| inject 1 bit (positions tested: ...) | SEC | | |
| inject 2 bits | DED | | |
| inject 3 bits (optional) | SEC (wrong data) | | |

## Implementation results (fill in from Vivado reports)

| Metric | Value |
|---|---|
| LUTs / FFs / BRAM (whole design) | |
| LUTs / FFs of encoder + decoder only | |
| Worst negative slack @ 100 MHz | |
| Date, Vivado version, board | |
