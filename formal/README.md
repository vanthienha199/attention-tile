# Formal cross-check attempt

`cross.eqy` tries to formally prove the agent-written design (`build/scorer.v`)
equivalent to the independently hand-written reference (`model/ref_scorer.v`)
using EQY with sequential induction at depth 24.

Result, honestly: the 16 trivial pin partitions (`uio_oe.*`, `uio_out.*`) prove
in about a second each. The real data-path partitions (`uo_out.*`) did not
converge, first with the default smtbmc solver in 15 minutes, then with
bitwuzla given two hours. The 64-entry score memory plus the argmax comparison
tree is simply a hard induction problem at this depth.

So no formal equivalence is claimed anywhere in this project. The verification
story rests on the 7968-cycle byte-exact simulation against the executable
spec across two independently seeded vector sets, plus the gate-level netlist
test in the Tiny Tapeout flow. The config is kept here in case someone wants
to take another swing at it with a better strategy.
