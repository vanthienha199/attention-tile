#!/usr/bin/env python3
"""Executable spec for the attention scorer. Byte-level, cycle-by-cycle.

Reads stimulus lines "cmd data" (two hex bytes, or the word RESET) and prints the
expected uo_out byte after that clock edge, one line per line of stimulus. The DUT
simulation is compared against this output exactly.
"""
import sys


def sat16(x):
    return max(-32768, min(32767, x))


def to_s8(b):
    return b - 256 if b >= 128 else b


class Scorer:
    def __init__(self):
        self.reset()

    def reset(self):
        self.q = [0] * 8      # query buffer, written in place
        self.qfill = 0        # next q index to fill (0..8; 8 = complete)
        self.acc = 0          # partial key accumulator
        self.dim = 0          # next key dimension (0..7)
        self.best = -32768
        self.best_idx = 0
        self.key_idx = 0
        self.read_phase = 0
        self.out = 0

    def step(self, cmd, data):
        if cmd != 3:
            self.read_phase = 0
        if cmd == 1:  # LOAD_Q
            self.acc = 0      # interrupting a partial key discards it
            self.dim = 0
            if self.qfill >= 8:
                self.qfill = 0
            self.q[self.qfill] = to_s8(data)
            self.qfill += 1
            if self.qfill == 8:
                self.best = -32768
                self.best_idx = 0
                self.key_idx = 0
        elif cmd == 2:  # STREAM_K
            if self.qfill < 8:
                self.qfill = 0  # interrupting a partial query resets the fill
            if self.key_idx <= 63:
                self.acc = sat16(self.acc + self.q[self.dim] * to_s8(data))
                self.dim += 1
                if self.dim == 8:
                    if self.acc > self.best:
                        self.best = self.acc
                        self.best_idx = self.key_idx
                    self.key_idx += 1
                    self.acc = 0
                    self.dim = 0
        elif cmd == 3:  # READ
            ph = self.read_phase % 3
            if ph == 0:
                self.out = self.best_idx & 0x3F
            elif ph == 1:
                self.out = (self.best & 0xFFFF) >> 8
            else:
                self.out = self.best & 0xFF
            self.read_phase += 1
        else:  # IDLE
            self.acc = 0      # interrupting a partial key discards it
            self.dim = 0
            if self.qfill < 8:
                self.qfill = 0
        return self.out


def main():
    src = open(sys.argv[1]) if len(sys.argv) > 1 else sys.stdin
    m = Scorer()
    for line in src:
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if line == "RESET":
            m.reset()
            print("00")
            continue
        cmd_s, data_s = line.split()
        out = m.step(int(cmd_s, 16), int(data_s, 16))
        print(f"{out & 0xFF:02x}")


if __name__ == "__main__":
    main()
