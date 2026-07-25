# Formal cross-checks

Two independent implementations of the same spec exist in this repo: the
agent-written design (`build/scorer.v`, generated from `hw/scorer.tlv`) and the
hand-written reference (`model/ref_scorer.v`). Two formal attempts were made to
relate them.

## Bounded equivalence: PROVED (depth 18)

`bmc/` holds a miter (`bmc_top.sv`): both implementations receive identical
free inputs, reset is held for the first two cycles, and all three outputs are
asserted equal on every cycle after. `sby` in BMC mode with bitwuzla proves
this exhaustively to depth 18 on the shipped 994-cell design:

    SBY [cross_bmc] DONE (PASS, rc=0)

Precisely: there is no input sequence of any kind, any commands, any data, any
interleaving, that makes the two implementations diverge on any output within
the first 15 cycles after reset release. That window covers a full query load
plus arbitrary command interleavings, exhaustively, which no finite testbench
can claim. It does not cover longer transactions such as a full 64-key stream;
beyond this depth the solver cost grows steeply (the pre-shrink 1054-cell
design could not clear depth 18 in over four hours, the smaller design proved
it in about 35 minutes).

## Unbounded equivalence: NOT proved

`cross.eqy` attempts full sequential equivalence with EQY at induction depth
24. The 16 trivial pin partitions prove in about a second each; the data-path
partitions (`uo_out.*`) did not converge with smtbmc in 15 minutes or bitwuzla
in two hours. The 64-entry score memory plus the argmax comparison tree is a
hard induction problem, and no unbounded claim is made anywhere in this
project.

The end-to-end verification story therefore rests on: the bounded proof above,
the 7968-cycle byte-exact simulation across two independently seeded vector
sets, and the gate-level netlist test in the Tiny Tapeout flow.
