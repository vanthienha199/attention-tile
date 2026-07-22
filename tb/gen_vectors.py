#!/usr/bin/env python3
"""Generate the stimulus file for the scorer testbench. Deterministic (fixed seed).

Covers: full random traffic, saturation extremes, ties, interrupted loads and
streams, the 64-key limit, read rotation, and mid-run reset.
"""
import random
import sys

random.seed(20260722)
lines = []


def op(cmd, data=0):
    lines.append(f"{cmd:x} {data & 0xFF:02x}")


def load_q(vals):
    for v in vals:
        op(1, v)


def stream_k(vals):
    for v in vals:
        op(2, v)


def reads(n):
    for _ in range(n):
        op(3)


# 1. Directed: known query, known keys, easy to eyeball.
load_q([1, 2, 3, 4, 5, 6, 7, 8])
stream_k([1, 1, 1, 1, 1, 1, 1, 1])      # score 36
stream_k([2, 2, 2, 2, 2, 2, 2, 2])      # score 72 -> winner key 1
stream_k([0x80] * 8)                     # -128s: very negative
reads(7)

# 2. Saturation: q=127*8 vs k=127*8 saturates positive.
load_q([127] * 8)
stream_k([127] * 8)
reads(4)
stream_k([0x80] * 8)                     # heavy negative accumulate, saturates low
reads(4)

# 3. Tie handling: two identical keys, first must win.
load_q([10, 0, 0, 0, 0, 0, 0, 5])
stream_k([3, 0, 0, 0, 0, 0, 0, 2])
stream_k([3, 0, 0, 0, 0, 0, 0, 2])
reads(4)

# 4. Interrupted key: 5 bytes then IDLE, then a full key. Index must be 0 for it.
load_q([1] * 8)
stream_k([9, 9, 9, 9, 9])
op(0)
stream_k([4] * 8)
reads(4)

# 5. Interrupted query load then full reload.
load_q([7, 7, 7])
op(0)
load_q([2] * 8)
stream_k([1] * 8)
reads(4)

# 6. 64-key limit: 70 keys, later ones ignored past 63.
load_q([1, 0, 0, 0, 0, 0, 0, 0])
for j in range(70):
    stream_k([(j % 5) + 1, 0, 0, 0, 0, 0, 0, 0])
reads(7)

# 7. Mid-run reset then fresh traffic.
lines.append("RESET")
reads(4)
load_q([5] * 8)
stream_k([1] * 8)
reads(4)

# 8. Random soak: mixed commands, biased toward complete transactions.
for _ in range(400):
    r = random.random()
    if r < 0.15:
        load_q([random.randrange(256) for _ in range(8)])
    elif r < 0.70:
        stream_k([random.randrange(256) for _ in range(8)])
    elif r < 0.80:
        # partial garbage
        n = random.randrange(1, 8)
        for _ in range(n):
            op(random.choice([1, 2]), random.randrange(256))
        op(0)
    elif r < 0.95:
        reads(random.randrange(1, 6))
    else:
        op(0, random.randrange(256))

out = sys.argv[1] if len(sys.argv) > 1 else "/dev/stdout"
with open(out, "w") as f:
    f.write("\n".join(lines) + "\n")
print(f"{len(lines)} stimulus lines", file=sys.stderr)
