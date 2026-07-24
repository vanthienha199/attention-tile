# attention-tile

I asked a set of LLM agents to design a piece of silicon for me, with one rule: they
never get to judge their own work. This repo is the whole experiment.

The design is a streaming attention scorer, the score-and-select half of transformer
attention: store an int8 query, stream int8 keys one byte per cycle, share one
multiplier and one saturating accumulator across dimensions, track the argmax. Small
enough for a single Tiny Tapeout tile, real enough to be the primitive every
transformer spends most of its time on.

## How the loop works

- `docs/SPEC.md` and `model/golden.py` are the contract: a byte-exact executable spec.
- `agentflow/e10_genesis.py` asks a model (DeepSeek first, Claude on escalation) for a
  complete TL-Verilog file. That is the only thing a model ever produces here.
- `scripts/check.sh` is the judge, and it is plain code: SandPiper compile, two
  independently seeded stimulus sets (7968 cycles) compared byte-for-byte against the
  golden model, and a latch-free synthesis check. A failing attempt gets the error,
  the generated Verilog around the failing line, and its own previous file back as
  feedback, then tries again.
- Every attempt is kept in `agentflow/`, including the failures.

## What actually happened

The first passing design cost $0.008 and 3 attempts, and it was wrong. My first
stimulus set tested the 64-key limit with keys that could never win, so the rule had
no discriminating coverage; a second seed with a would-be-winning 65th key exposed
that v1 scored it. The hand-written reference (`model/ref_scorer.v`) passed both sets
unchanged, so the harness was sound and the bug was real. The agents then repaired
the design against the hardened gate over three more runs. Convergence only happened
after two pipeline changes: attempts carry their previous file (repair instead of
regenerate), and syntax feedback includes the generated Verilog, because a line
number in a file the model cannot see is not feedback.

Total model cost for the final hardened design, including every failed attempt and
the buggy v1: about 63 cents. The v1 bug file is kept at
`agentflow/design_v1_64key_bug.tlv`.

## Silicon

The Tiny Tapeout submission lives in a separate repo built from the TT template, with
the same conformance vectors run in cocotb at RTL and gate level, through the sky130
GDS flow. The chip goes out on the TTSKY26c shuttle.

## Where this sits in the literature

Recent benchmarks for LLM-generated RTL (NotSoTiny, arXiv:2512.20823; FormalRTL,
arXiv:2603.08738; the ASPDAC'26 LLM-DV survey) converge on the same verification
shape used here: candidates judged against an independent golden reference by
deterministic tooling, with formal equivalence as the gold standard. The formal
attempt for this design is documented honestly in `formal/README.md`. The same
benchmarks also report that LLM-written RTL usually trails hand-written RTL on area
and delay, which is an open experiment here: the tile sits at ~86% utilization, and
shrinking it with the same pipeline and the same byte-exact gate as the correctness
constraint is the natural next run.

On the architecture side, the datapath is the score-and-select half of attention;
the softmax half has become practical for tiles this small through integer
power-of-two schemes (Softermax; E2Softmax; IntAttention, arXiv:2511.21513), which
replace e^x with shift/add logic. That is the intended growth path for a future
shuttle slot.
