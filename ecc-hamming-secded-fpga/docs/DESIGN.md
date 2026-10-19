# Design

## Code construction

A SECDED code for `k` data bits uses `r` Hamming parity bits with `2^r >= k + r + 1`, plus one overall parity bit.

| Code | k | r | total n | overhead |
|---|---|---|---|---|
| Hamming(72,64) | 64 | 7 | 72 | 8/64 = 12.5% |
| Hamming(13,8) | 8 | 4 | 13 | 5/8 = 62.5% |

Classic interleaved layout: positions `1..k+r` hold parity bits at the powers of two (1, 2, 4, 8, ...) and data bits
everywhere else. Parity bit `p_i` (at position `2^i`) is the XOR of every data bit whose position has bit `i` set.
The overall parity bit makes the parity of the whole word even.

**Hamming(13,8) equations** (D0..D7 = `data_in[0..7]`, placed at positions 3, 5, 6, 7, 9, 10, 11, 12):

```
P1 = D0 ^ D1 ^ D3 ^ D4 ^ D6
P2 = D0 ^ D2 ^ D3 ^ D5 ^ D6
P4 = D1 ^ D2 ^ D3 ^ D7
P8 = D4 ^ D5 ^ D6 ^ D7
P13 (overall) = XOR of the 12 bits above
code_out = { P13, D7 D6 D5 D4 P8 D3 D2 D1 P4 D0 P2 P1 }
```

Gate-level view of one parity tree: [`img/xor_tree_parity_P1.png`](img/xor_tree_parity_P1.png).

**Worked example.** `data_in = 8'b10110101` gives D0=1, D1=0, D2=1, D3=0, D4=1, D5=1, D6=0, D7=1, so
P1=0, P2=1, P4=0, P8=1. The 12-bit field is `1011 1010 0110`, it contains seven 1s so P13=1, and
`code_out = 1_1011_1010_0110` (binary `1101110100110`), matching the RTL simulation
([waveform](img/waveform_hamming_13_8.png)).

## Decoding rule

The decoder recomputes the syndrome `S` (XOR of the positions of all set bits) and the overall parity check `P`:

| S | P | meaning | action | flags |
|---|---|---|---|---|
| 0 | 0 | no error | none | - |
| != 0 | 1 | one error at position S | flip it | `sec` |
| 0 | 1 | error in the overall parity bit only | data unaffected | `sec` |
| != 0 | 0 | two errors | cannot correct | `ded` |

Odd-weight errors (1, 3, 5, ...) always give `P = 1`, so they can never reach the `ded` row. That is the root of
the silent-miscorrection result for 3 errors. If `S` points outside the codeword (possible because the code is
shortened) the RTL performs no flip but still reports `sec`.

## Modules (`rtl/sram64/`)

| File | Role |
|---|---|
| `hamming_encoder.v` | 64 -> 72 bit encoder, combinational (bounded loops unroll to XOR trees) |
| `hamming_decoder.v` | 72 -> 64 bit decoder, outputs `sec` / `ded` |
| `ecc_sram_wrapper.v` | Block RAM of 72-bit words, encode on write, decode on read, fault-injection port |
| `fault_injector.v` | Edge-triggered one-cycle pulse to flip a chosen stored bit |
| `stats_logger.v` | Counters for reads / corrected / uncorrectable (currently not routed to a visible output) |
| `top_ecc_demo.v` | Board demo: buttons -> test FSM -> LEDs |

`rtl/codec13_8/hamming_13_8.v` holds the 8-bit codec with the `clk / rst / enable` interface from the lab spec.

## Timing and behaviour

- Write: data is encoded combinationally and stored in the same cycle.
- Read: 2-cycle latency from `addr` to `dout`; `dout_valid` marks valid data. `dout_valid` is high continuously
  while the memory is idle, so it must not be used as a "new result ready" strobe (see the debugging log).
- Single port: fault injection has priority over write, which has priority over read.

## Board demo (`top_ecc_demo`)

| Control | Effect | Expected LED |
|---|---|---|
| `btn[0]` step | write a new test word to the next address and read it back | `led[0]` PASS |
| `sw[6:0]` + `btn[1]` inject | flip stored bit `sw` (0..71) of the current word, read back | `led[1]` SEC |
| inject twice (different bits) | two errors in one word | `led[2]` DED |
| `btn[2]` clear | clear stats counters | - |
| - | free-running counter | `led[3]` heartbeat |

The FSM waits a fixed 8-cycle settle time after each operation before latching the LEDs. This behaviour is
checked by `tb/tb_top_ecc_demo.v`.
