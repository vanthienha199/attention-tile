#!/usr/bin/env python3
"""Second, nastier stimulus set (independent seed). Targets the cases the first set
under-stresses: READ interrupting partial transactions, the 63/64 key boundary,
saturation recovery, command thrash, and long READ rotations.
"""
import random
import sys

random.seed(99120731)
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


# 1. READ interrupting a partial key: partial accumulate must be discarded.
load_q([4, 3, 2, 1, 0, 0xFF, 0xFE, 0x7F])
stream_k([10, 10, 10])
reads(2)                       # interrupt: discard partial
stream_k([1] * 8)              # this is key 0
reads(6)

# 2. READ interrupting a partial query: fill resets, old buffer bytes remain.
load_q([9, 9, 9, 9])
reads(1)
load_q([1, 2, 3, 4, 5, 6, 7, 8])   # full fresh query
stream_k([1, 0, 0, 0, 0, 0, 0, 0])
reads(4)

# 3. Exactly 64 keys, then the 65th and 66th must be ignored.
load_q([2, 0, 0, 0, 0, 0, 0, 0])
for j in range(64):
    stream_k([j % 3, 0, 0, 0, 0, 0, 0, 0])
stream_k([0x7F, 0, 0, 0, 0, 0, 0, 0])   # would win if not ignored
stream_k([0x7F, 0, 0, 0, 0, 0, 0, 0])
reads(7)

# 4. Saturate low then recover: best must track correctly across saturation.
load_q([0x80] * 8)                       # q = -128 everywhere
stream_k([0x7F] * 8)                     # very negative score (saturates low)
stream_k([0x80] * 8)                     # very positive score (saturates high)
reads(5)

# 5. Long READ rotation: 10 READs in a row cycle idx,hi,lo,idx,hi,lo,...
load_q([1, 1, 1, 1, 1, 1, 1, 1])
stream_k([5] * 8)
reads(10)

# 6. Command thrash: rapid alternation, no complete transactions.
for _ in range(30):
    op(random.choice([0, 1, 2, 3]), random.randrange(256))
op(0)

# 7. Fresh query after thrash must still work.
load_q([3] * 8)
stream_k([2] * 8)
reads(4)

# 8. Two resets close together with traffic in between.
lines.append("RESET")
load_q([6] * 8)
lines.append("RESET")
reads(3)
load_q([1, 0, 1, 0, 1, 0, 1, 0])
stream_k([1] * 8)
reads(4)

# 9. Random soak, different distribution: heavier on interrupts and reads.
for _ in range(600):
    r = random.random()
    if r < 0.20:
        load_q([random.randrange(256) for _ in range(8)])
    elif r < 0.55:
        stream_k([random.randrange(256) for _ in range(8)])
    elif r < 0.75:
        n = random.randrange(1, 8)
        kind = random.choice([1, 2])
        for _ in range(n):
            op(kind, random.randrange(256))
        op(random.choice([0, 3]), random.randrange(256))
    elif r < 0.95:
        reads(random.randrange(1, 8))
    else:
        lines.append("RESET")

out = sys.argv[1] if len(sys.argv) > 1 else "/dev/stdout"
with open(out, "w") as f:
    f.write("\n".join(lines) + "\n")
print(f"{len(lines)} stimulus lines", file=sys.stderr)
