#!/usr/bin/env python3
"""E12: agent-driven pipelining voi gate tat dinh.
Huong Steve chot (DM Jul 27): "TLV can get you safely to a pipelined
implementation" - sim bac cau spec->TLV dau tien, tu do TLV retime an toan.
Task: chia datapath cua scorer vao nhieu stage TLV de RUT NGAN critical path,
GIU NGUYEN hanh vi I/O tung byte (check.sh 7968 cycle van la toa an).
Metric: do sau topological (yosys ltp) cua build/scorer.v - champion chi doi
khi PASS check.sh va depth GIAM. hw/scorer.tlv restore ve champion khi ket thuc.
Usage: MM_PROVIDERS="deepseek:3,claude:3" e12_pipeline.py
"""
import os, re, subprocess, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from e10_genesis import ROOT, MAX_COST, TLV_GUIDE, SYSTEM, read, call_retry, run_checks, extract

DESIGN = os.path.join(ROOT, "hw", "scorer.tlv")
OUTDIR = os.path.join(ROOT, "agentflow", "pipeline")
os.makedirs(OUTDIR, exist_ok=True)

cost = {"deepseek": 0.0, "claude": 0.0}

def track(provider, i, o):
    c = (i*0.14 + o*0.28)/1e6 if provider == "deepseek" else (i*3.0 + o*15.0)/1e6
    cost[provider] += c
    if cost[provider] > MAX_COST[provider]:
        print(f"!!! COST CAP {provider}", flush=True)
        raise SystemExit(2)
    return c

def measure_depth():
    r = subprocess.run(["docker", "run", "--rm",
        "-v", ROOT + ":/workspace/at:rw", "-w", "/workspace/at",
        "--entrypoint", "bash", "rv-tournament:latest", "-lc",
        "export PATH=/opt/oss-cad-suite/bin:$PATH; "
        "yosys -p 'read_verilog -sv build/scorer.v; hierarchy -top tt_um_hale_attn_scorer; proc; opt; ltp' 2>&1"],
        capture_output=True, text=True, timeout=300)
    m = re.search(r"length=(\d+)", r.stdout + r.stderr)
    return int(m.group(1)) if m else None

PIPE_GUIDE = r"""
# Pipelining guidance (TL-Verilog staging)
- Split work across stages by moving statements from @0 into @1 (or deeper).
  SandPiper inserts the pipeline flops automatically; a signal assigned in @0
  and read in @1 is staged for free.
- The module's I/O behavior must stay EXACTLY the same cycle-for-cycle: outputs
  are checked byte-for-byte against a golden model. Retime INTERNAL computation
  only; use >>1 alignment to compensate where a consumer moved a stage later,
  so the visible timing of *uo_out does not change.
- State updates (<<1$x = ...) must keep their original per-cycle semantics.
- The win condition is a shorter combinational path (the multiply-accumulate
  chain and the argmax compare are the long paths), not fewer cells.
"""

def build_user(champion_body, champion_depth, feedback=None, last_body=None):
    u = ("# Task\n\n"
         "Below is a WORKING TL-Verilog implementation of an attention scorer tile. "
         f"Its longest combinational path is {champion_depth} cells (yosys ltp). Your "
         "job is to SHORTEN that path by pipelining internal computation across TLV "
         "stages, while keeping I/O behavior byte-for-byte identical over 7968 checked "
         "cycles. Do NOT change the module name, ports, or the visible cycle timing of "
         "any output.\n\n"
         "# Current design (the one to pipeline)\n\n" + champion_body + "\n\n"
         "# Specification it must keep matching\n\n" + read("docs/SPEC.md") + "\n"
         + TLV_GUIDE + PIPE_GUIDE +
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
    if not ok:
        print("baseline khong pass, dung")
        return
    base = measure_depth()
    if base is None:
        print("khong doc duoc ltp depth, dung")
        return
    champion_depth = base
    print(f"baseline: depth {base} (PASS)", flush=True)
    providers = [tuple(x.split(":")) for x in
                 os.environ.get("MM_PROVIDERS", "deepseek:3,claude:3").split(",")]
    feedback = last_body = None
    n = 0
    try:
        for provider, tries in providers:
            for a in range(1, int(tries) + 1):
                n += 1
                print(f"  [{provider} #{a}] goi API ...", flush=True)
                resp, i, o = call_retry(provider, build_user(champion_body, champion_depth, feedback, last_body))
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
                depth = measure_depth() if ok else None
                if ok and depth is not None and depth < champion_depth:
                    print(f"  [{provider} #{a}] PASS, depth {depth} (was {champion_depth}) NEW CHAMPION (${c:.4f})", flush=True)
                    champion_body, champion_depth = body, depth
                    feedback = (f"Good: your design passed and the longest path dropped to {depth}. "
                                f"Pipeline it further if you can.")
                elif ok:
                    print(f"  [{provider} #{a}] PASS nhung depth {depth} >= {champion_depth}, tu choi (${c:.4f})", flush=True)
                    feedback = (f"Your design is CORRECT but its longest path is {depth} cells, not "
                                f"shorter than the current {champion_depth}. Move real computation "
                                f"across stages; cosmetic changes do not shorten the path.")
                else:
                    tail = "\n".join(out.strip().splitlines()[-25:])
                    print(f"  [{provider} #{a}] FAIL check (${c:.4f})", flush=True)
                    feedback = "Checks FAILED:\n" + tail
    finally:
        with open(DESIGN, "w") as f:
            f.write(champion_body)
        print("\n===== KET QUA =====")
        if champion_depth < base:
            print(f"baseline depth {base} -> champion {champion_depth} ({100.0*(base-champion_depth)/base:.1f}% ngan hon)")
        else:
            print(f"khong rut ngan duoc (depth {base} giu nguyen)")
        print(f"cost: ds ${cost['deepseek']:.4f} + cl ${cost['claude']:.4f}")

if __name__ == "__main__":
    main()
