#!/usr/bin/env python3
"""Encode vectors.txt for the Verilog testbench: RESET lines become 'f 00'."""
import sys

src, dst = sys.argv[1], sys.argv[2]
with open(src) as f, open(dst, "w") as g:
    for line in f:
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        g.write("f 00\n" if line == "RESET" else line + "\n")
