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

echo "=== stage 2+3: simulate and compare (both vector sets) ==="
iverilog -g2012 -o build/sim.vvp "$SRC" tb/tb.v > build/iverilog.log 2>&1
if [ $? -ne 0 ]; then
  echo "IVERILOG FAILED:"
  cat build/iverilog.log
  exit 3
fi
for GEN in gen_vectors gen_vectors_extra; do
  python3 tb/$GEN.py tb/vectors.txt 2>/dev/null
  python3 tb/gen_tb_input.py tb/vectors.txt tb/vectors_encoded.txt
  timeout 120 vvp build/sim.vvp > build/vvp.log 2>&1
  grep -q "TB_DONE" build/vvp.log || { echo "SIM DID NOT FINISH ($GEN):"; tail -20 build/vvp.log; exit 3; }
  python3 model/golden.py tb/vectors.txt > build/gold_out.txt
  if ! diff -q build/gold_out.txt build/dut_out.txt > /dev/null; then
    total=$(wc -l < build/gold_out.txt)
    mism=$(paste build/gold_out.txt build/dut_out.txt | awk '$1 != $2' | wc -l)
    echo "MISMATCH in $GEN: $mism of $total cycles differ. First 10:"
    paste build/gold_out.txt build/dut_out.txt | awk '$1 != $2 {print NR": gold="$1" dut="$2}' | head -10
    exit 4
  fi
  echo "ok $GEN ($(wc -l < build/gold_out.txt | tr -d ' ') cycles match)"
done

echo "=== stage 4: synth sanity ==="
yosys -q -l build/yosys.log -p "read_verilog -sv $SRC; hierarchy -top tt_um_hale_attn_scorer; proc; opt; stat" \
  > /dev/null 2>&1
if [ $? -ne 0 ]; then
  echo "YOSYS FAILED:"
  tail -20 build/yosys.log
  exit 5
fi
if grep -qE 'Latch inferred|\$(a?dlatch|dlatchsr)' build/yosys.log; then
  echo "LATCHES INFERRED:"
  grep -E 'Latch inferred|\$(a?dlatch|dlatchsr)' build/yosys.log
  exit 5
fi
cells=$(awk '/^===/{s=1; next} s && /^[[:space:]]+[0-9]+[[:space:]]/{sum += $1} END{print sum+0}' build/yosys.log)
echo "Number of cells: $cells"
echo "ALL CHECKS PASSED"
