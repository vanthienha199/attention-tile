# attention-tile: streaming int8 attention scorer

A minimal silicon primitive for transformer attention scoring, sized for one Tiny
Tapeout tile. It computes dot products between a stored query vector and a stream of
key vectors, and tracks the best-scoring key. This is the score-and-select half of
attention: score = q . k, winner = argmax over keys.

## Parameters

- D = 8 dimensions per vector
- Element type: int8 (two's complement, -128..127)
- Accumulator: int16 with saturation to [-32768, 32767]
- Key index: 6 bits (up to 64 keys per query; after key 63 the scorer
  ignores further STREAM_K bytes until a new query completes)

## Interface (Tiny Tapeout standard)

- `clk`, `rst_n` (active-low reset)
- `ui_in[7:0]` data byte in
- `uo_out[7:0]` result byte out
- `uio_in[1:0]` command
- All other uio pins unused (uio_oe driven 0, uio_out 0)

## Command protocol

Commands are sampled on every rising clock edge. `cmd = uio_in[1:0]`.

| cmd | name | behavior |
|-----|------|----------|
| 00 | IDLE | no state change; uo_out holds its current value |
| 01 | LOAD_Q | this cycle's ui_in byte is q[i] for the next unfilled index i (0..7). The 8th byte completes the query, clears best score to -32768, best index to 0, and key counter to 0. Extra LOAD_Q bytes after the 8th restart the fill at index 0 (a new query). |
| 10 | STREAM_K | this cycle's ui_in byte is k[j] for dimension j of the current key. The scorer multiplies it by q[j] and accumulates with int16 saturation. The 8th byte completes the key: if score > best (strictly), best = score and best_index = current key index. Key index then increments. Ties keep the earlier key. |
| 11 | READ | uo_out presents a result byte, rotating each READ cycle: 1st READ after any non-READ shows {2'b00, best_index[5:0]}, 2nd shows best score high byte, 3rd shows best score low byte, 4th wraps to best_index again, and so on. |

Notes:
- A partially streamed key (fewer than 8 STREAM_K bytes before another command
  interrupts) is DISCARDED: the dimension counter and its partial accumulator reset,
  and the key index does not increment.
- LOAD_Q writes the query buffer in place, one byte per cycle. Interrupting a partial
  load resets the fill counter to 0; bytes already written stay in the buffer, so a
  query is only meaningful after 8 uninterrupted LOAD_Q bytes. This keeps the
  hardware to a single 8-byte buffer.
- Reset (rst_n = 0) clears everything: q = all zeros, best = -32768, best_index = 0,
  key count = 0, uo_out = 0.
- Saturation applies at every accumulate step, not only at the end.
- During non-READ cycles, uo_out holds its last value (0 after reset).

## Sizing intent

Serial MAC: one int8 x int8 multiplier, one int16 saturating adder, an 8-byte query
register file, one int16 best register, 6-bit index registers, and a small FSM.
