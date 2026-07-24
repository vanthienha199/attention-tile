#!/usr/bin/env python3
"""E11: agent-driven area reduction voi gate tat dinh.
Van de tu van lieu 2026 (NotSoTiny/FormalRTL): LLM-RTL thua tay nguoi ve PPA.
Thi nghiem: cho chinh pipeline giam yosys cell count cua design dang pass,
rang buoc dung dan giu nguyen = check.sh (7968 cycle byte-exact + latch check).
Champion chi doi khi PASS va cells GIAM. hw/scorer.tlv luon duoc restore ve
champion khi ket thuc (ke ca crash).
Usage: MM_PROVIDERS="deepseek:4,claude:4" e11_shrink.py
"""
import os, re, sys, time, shutil

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from e10_genesis import (ROOT, MAX_COST, TLV_GUIDE, SYSTEM, read, call_retry,
                         run_checks, extract)

DESIGN = os.path.join(ROOT, "hw", "scorer.tlv")
OUTDIR = os.path.join(ROOT, "agentflow", "shrink")
os.makedirs(OUTDIR, exist_ok=True)

cost = {"deepseek": 0.0, "claude": 0.0}

def track(provider, i, o):
    c = (i*0.14 + o*0.28)/1e6 if provider == "deepseek" else (i*3.0 + o*15.0)/1e6
    cost[provider] += c
    if cost[provider] > MAX_COST[provider]:
        print(f"!!! COST CAP {provider}", flush=True)
        raise SystemExit(2)
    return c

def cells_of(out):
    m = re.search(r"Number of cells:\s*(\d+)", out)
    return int(m.group(1)) if m else None

def build_user(champion_body, champion_cells, feedback=None, last_body=None):
    u = ("# Task\n\n"
         "Below is a WORKING TL-Verilog implementation of an attention scorer tile. "
         f"It synthesizes to {champion_cells} cells (yosys generic synth). Your job is "
         "to REDUCE the cell count while keeping behavior byte-for-byte identical: the "
         "design is checked against a golden model over 7968 cycles and must stay "
         "latch-free. Think resource sharing, narrower state, cheaper mux structures, "
         "removing redundant terms. Do NOT change the module name, ports, or protocol.\n\n"
         "# Current design (the one to shrink)\n\n" + champion_body + "\n\n"
         "# Specification it must keep matching\n\n" + read("docs/SPEC.md") + "\n"
         + TLV_GUIDE +
         "\nReply with EXACTLY this format (no markdown fences, no commentary):\n"
         "===FILE: scorer.tlv===\n<complete file contents>\n===END===\n")
    if feedback:
        u += "\n# Previous attempt result:\n\n" + feedback[-3500:]
        if last_body:
            u += "\n\n# Your previous attempt:\n\n" + last_body
        u += "\n\nReply with the complete corrected file."
    return u

def main():
    champion_body = open(DESIGN).read()
    ok, out = run_checks()
    base = cells_of(out)
    if not ok or base is None:
        print("baseline khong pass hoac khong doc duoc cell count, dung")
        return
    champion_cells = base
    print(f"baseline: {base} cells (PASS)", flush=True)
    providers = [tuple(x.split(":")) for x in
                 os.environ.get("MM_PROVIDERS", "deepseek:4,claude:4").split(",")]
    feedback = last_body = None
    n = 0
    try:
        for provider, tries in providers:
            for a in range(1, int(tries) + 1):
                n += 1
                print(f"  [{provider} #{a}] goi API ...", flush=True)
                resp, i, o = call_retry(provider, build_user(champion_body, champion_cells, feedback, last_body))
                c = track(provider, i, o)
                body = extract(resp)
                if not body:
                    print(f"  [{provider} #{a}] khong parse duoc (${c:.4f})")
                    feedback = "Your reply did not follow the ===FILE:===/===END=== format."
                    continue
                with open(os.path.join(OUTDIR, f"attempt_{provider}_{n}.tlv"), "w") as f:
                    f.write(body)
                with open(DESIGN, "w") as f:
                    f.write(body)
                last_body = body
                ok, out = run_checks()
                cells = cells_of(out)
                if ok and cells is not None and cells < champion_cells:
                    print(f"  [{provider} #{a}] PASS, {cells} cells (was {champion_cells}) NEW CHAMPION (${c:.4f})", flush=True)
                    champion_body, champion_cells = body, cells
                    feedback = (f"Good: your design passed and shrank to {cells} cells. "
                                f"Shrink it further if you can.")
                elif ok:
                    print(f"  [{provider} #{a}] PASS nhung {cells} cells >= {champion_cells}, tu choi (${c:.4f})", flush=True)
                    feedback = (f"Your design is CORRECT but synthesizes to {cells} cells, "
                                f"not smaller than the current {champion_cells}. Find real "
                                f"logic savings, not cosmetic changes.")
                else:
                    tail = "\n".join(out.strip().splitlines()[-25:])
                    print(f"  [{provider} #{a}] FAIL check (${c:.4f})", flush=True)
                    feedback = "Checks FAILED:\n" + tail
    finally:
        with open(DESIGN, "w") as f:
            f.write(champion_body)
        print(f"\n===== KET QUA =====")
        print(f"baseline {base} -> champion {champion_cells} cells "
              f"({100.0*(base-champion_cells)/base:.1f}% giam)" if champion_cells < base
              else f"khong giam duoc ({base} cells giu nguyen)")
        print(f"cost: ds ${cost['deepseek']:.4f} + cl ${cost['claude']:.4f}")

if __name__ == "__main__":
    main()
