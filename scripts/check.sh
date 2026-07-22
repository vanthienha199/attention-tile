#!/usr/bin/env bash
# Deterministic acceptance gate for the scorer design. Run from the repo root
# (inside the rv-tournament container). Fails loudly at the first broken stage.
#
# Stages:
#   1. SandPiper: hw/scorer.tlv -> build/scorer.v (skipped if hw/scorer.v exists
#      and no .tlv is present, so the same gate works for plain-Verilog stages)
#   2. Lint/elaborate + simulate with the file-driven testbench
#   3. Compare DUT output byte-for-byte against the golden model
#   4. yosys generic synth sanity: no errors, no inferred latches, report cells
set -uo pipefail

mkdir -p build

echo "=== stage 1: compile TLV ==="
if [ -f hw/scorer.tlv ]; then
  rm -f build/scorer.v
  sandpiper-saas -i hw/scorer.tlv -o scorer.v --outdir build --inlineGen --noline --iArgs \
    > build/sandpiper.log 2>&1
  if [ ! -f build/scorer.v ]; then
    echo "SANDPIPER FAILED:"
    tail -30 build/sandpiper.log
    exit 2
  fi
  SRC=build/scorer.v
elif [ -f hw/scorer.v ]; then
  SRC=hw/scorer.v
else
  echo "NO DESIGN: hw/scorer.tlv (or hw/scorer.v) not found"
  exit 2
fi
echo "ok ($SRC)"

echo "=== stage 2: simulate ==="
python3 tb/gen_vectors.py tb/vectors.txt
python3 tb/gen_tb_input.py tb/vectors.txt tb/vectors_encoded.txt
iverilog -g2012 -o build/sim.vvp "$SRC" tb/tb.v > build/iverilog.log 2>&1
if [ $? -ne 0 ]; then
  echo "IVERILOG FAILED:"
  cat build/iverilog.log
  exit 3
fi
timeout 120 vvp build/sim.vvp > build/vvp.log 2>&1
grep -q "TB_DONE" build/vvp.log || { echo "SIM DID NOT FINISH:"; tail -20 build/vvp.log; exit 3; }
echo "ok"

echo "=== stage 3: compare vs golden ==="
python3 model/golden.py tb/vectors.txt > build/gold_out.txt
if ! diff -q build/gold_out.txt build/dut_out.txt > /dev/null; then
  total=$(wc -l < build/gold_out.txt)
  mism=$(paste build/gold_out.txt build/dut_out.txt | awk '$1 != $2' | wc -l)
  echo "MISMATCH: $mism of $total cycles differ. First 10:"
  paste build/gold_out.txt build/dut_out.txt | awk '$1 != $2 {print NR": gold="$1" dut="$2}' | head -10
  exit 4
fi
echo "ok ($(wc -l < build/gold_out.txt | tr -d ' ') cycles match)"

echo "=== stage 4: synth sanity ==="
yosys -q -p "read_verilog -sv $SRC; hierarchy -top tt_um_hale_attn_scorer; proc; opt; stat" \
  > build/yosys.log 2>&1
if [ $? -ne 0 ]; then
  echo "YOSYS FAILED:"
  tail -20 build/yosys.log
  exit 5
fi
if grep -qi "latch" build/yosys.log; then
  echo "LATCHES INFERRED:"
  grep -i latch build/yosys.log
  exit 5
fi
grep -E "Number of cells" build/yosys.log
echo "ALL CHECKS PASSED"
