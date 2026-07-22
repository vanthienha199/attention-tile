#!/usr/bin/env python3
"""E10: sinh thiet ke TLV tu spec bang agent, gate bang check.sh tat dinh.
Khac voi e6 (conversion): o day KHONG co golden RTL — golden la model Python
(executable spec) va agent chi duoc sinh hw/scorer.tlv. Judge la code, khong phai model.
Escalation: deepseek N lan -> claude M lan, feedback = output check.sh + vung mismatch.
Usage: MM_PROVIDERS="deepseek:5,claude:6" e10_genesis.py
"""
import os, sys, json, re, time, subprocess, urllib.request

ROOT = os.path.expanduser("~/projects/attention-tile")
MODEL_NAME = {"deepseek": "deepseek-v4-flash", "claude": "claude-sonnet-4-6"}
MAX_COST = {
    "deepseek": float(os.environ.get("MM_MAX_COST_DEEPSEEK", "1.5")),
    "claude": float(os.environ.get("MM_MAX_COST_CLAUDE", "2.5")),
}

TLV_GUIDE = r"""
# TL-Verilog quick reference (follow exactly)

File structure for a Tiny Tapeout module:

\m5_TLV_version 1d: tl-x.org
\m5
   use(m5-1.0)
\SV
   module tt_um_hale_attn_scorer (
     input  wire [7:0] ui_in,  output wire [7:0] uo_out,
     input  wire [7:0] uio_in, output wire [7:0] uio_out, output wire [7:0] uio_oe,
     input  wire ena, input wire clk, input wire rst_n);
   assign uio_out = 8'b0;
   assign uio_oe  = 8'b0;
   wire reset = ~rst_n;
\TLV
   |scorer
      @0
         ...logic here...
\SV
   endmodule

Rules learned the hard way:
- Indentation is significant: |pipe at 3 spaces, @stage at 6, statements at 9.
- $name[hi:lo] = expr; assigns a pipesignal (declared by assignment, never declared
  separately). Every $signal read must be assigned exactly once.
- The LHS bit range IS the declaration: omitting it ($x = ...) creates a 1-BIT signal,
  and any later $x[2:0] select fails elaboration. Every multi-bit signal must carry
  its range at the assignment, including in <<1$state[hi:lo] = ... form.
- <<1$state = expr; assigns the NEXT value of flop $state; reading $state gives the
  current (flopped) value. Use ternaries for enables: <<1$x = $we ? $new : $x;
  RESET EVERY STATE SIGNAL: <<1$x = *reset ? '0 : (...). SandPiper flops need this.
- *name reads/writes a Verilog signal declared in the \SV region (e.g. *ui_in,
  *uo_out, *reset). Assign module outputs with *uo_out = $out; inside @0.
- In \TLV expression context, Verilog system functions must be escaped: \$signed(...).
  Do NOT reference SandPiper-generated names from the \SV region.
- Arrays/memories do not exist as pipesignals. For the 8-byte query buffer use 8
  separate pipesignals ($q0..$q7) or an \SV_plus block with a real Verilog array:
  \SV_plus
     ...verilog here, $$sig[7:0] assigns pipesignal sig, \$readmemh escapes...
  Keeping the query as 8 pipesignals with a 3-bit select mux is simplest and small.
- signed arithmetic: declare widths explicitly and use \$signed() casts in TLV
  expressions, e.g. $prod[15:0] = \$signed($qsel) * \$signed($kbyte);
"""


def read(p):
    with open(os.path.join(ROOT, p)) as f:
        return f.read()


def build_user(feedback=None):
    u = ("# Task\n\n"
         "Write a complete TL-Verilog implementation of the attention scorer tile in a "
         "single file `scorer.tlv`. It must implement the spec below EXACTLY, "
         "byte-for-byte matching the golden model on every cycle. The testbench "
         "instantiates module `tt_um_hale_attn_scorer` with the standard Tiny Tapeout "
         "ports shown in the guide.\n\n"
         "# Specification\n\n" + read("docs/SPEC.md") +
         "\n\n# Golden model (executable spec, byte-exact)\n\n```python\n" +
         read("model/golden.py") + "```\n\n" + TLV_GUIDE +
         "\nReply with EXACTLY this format (no markdown fences, no commentary):\n"
         "===FILE: scorer.tlv===\n<complete file contents>\n===END===\n")
    if feedback:
        u += ("\n# Previous attempt FAILED the checks. Output:\n\n" + feedback[-4000:] +
              "\n\nFix the problem and reply with the complete corrected file.")
    return u


SYSTEM = ("You are an expert digital designer writing TL-Verilog for a Tiny Tapeout "
          "tile. You write complete, compilable files. Reply only in the requested "
          "file format.")


def call(provider, user):
    if provider == "deepseek":
        key = open(os.path.expanduser("~/.secrets/deepseek_key")).read().strip()
        req = urllib.request.Request("https://api.deepseek.com/chat/completions",
            data=json.dumps({"model": MODEL_NAME["deepseek"],
                "messages": [{"role": "system", "content": SYSTEM},
                             {"role": "user", "content": user}],
                "max_tokens": 16000, "temperature": 0.2}).encode(),
            headers={"Content-Type": "application/json", "Authorization": "Bearer " + key})
        d = json.load(urllib.request.urlopen(req, timeout=300))
        u = d.get("usage", {})
        msg = d["choices"][0]["message"]
        content = msg.get("content") or ""
        if not content:
            fr = d["choices"][0].get("finish_reason")
            rc = msg.get("reasoning_content") or ""
            print(f"    (deepseek content rong, finish_reason={fr}, reasoning={len(rc)} chars)", flush=True)
            content = rc  # may contain the file at the end; extractor will judge
        return content, u.get("prompt_tokens", 0), u.get("completion_tokens", 0)
    key = open(os.path.expanduser("~/.secrets/steve_anthropic_key")).read().strip()
    req = urllib.request.Request("https://api.anthropic.com/v1/messages",
        data=json.dumps({"model": MODEL_NAME["claude"], "max_tokens": 8000,
            "system": SYSTEM, "messages": [{"role": "user", "content": user}]}).encode(),
        headers={"Content-Type": "application/json", "x-api-key": key,
                 "anthropic-version": "2023-06-01"})
    d = json.load(urllib.request.urlopen(req, timeout=300))
    u = d.get("usage", {})
    return d["content"][0]["text"], u.get("input_tokens", 0), u.get("output_tokens", 0)


def call_retry(provider, user, tries=6):
    for k in range(tries):
        try:
            return call(provider, user)
        except Exception as e:
            print(f"    (network {type(e).__name__}, retry {k+1})", flush=True)
            time.sleep(min(60, 15 * (k + 1)))
    raise RuntimeError("network retries exhausted")


def run_checks():
    r = subprocess.run(["docker", "run", "--rm",
        "-v", ROOT + ":/workspace/at:rw", "-w", "/workspace/at",
        "--entrypoint", "bash", "rv-tournament:latest", "-lc",
        "export PATH=/home/claude/mmvenv/bin:/opt/oss-cad-suite/bin:$PATH; "
        "bash scripts/check.sh 2>&1"],
        capture_output=True, text=True, timeout=900)
    out = r.stdout + r.stderr
    return "ALL CHECKS PASSED" in out, out


def enrich(out):
    # On a mismatch, show the stimulus context around the first differing cycle.
    m = re.search(r"^(\d+): gold=", out, re.M)
    if not m:
        return out
    n = int(m.group(1))
    try:
        stim = open(os.path.join(ROOT, "tb/vectors_encoded.txt")).read().splitlines()
        lo, hi = max(0, n - 12), min(len(stim), n + 3)
        ctx = "\n".join(f"cycle {i+1}: cmd={stim[i].split()[0]} data={stim[i].split()[1]}"
                        for i in range(lo, hi))
        out += ("\n\n# Stimulus around the first mismatch (cmd 1=LOAD_Q 2=STREAM_K "
                "3=READ 0=IDLE f=RESET):\n" + ctx)
    except OSError:
        pass
    return out


def extract(text):
    m = re.search(r"===FILE: scorer\.tlv===\n(.*?)\n?===END===", text, re.S)
    if m:
        return m.group(1)
    # Lenient fallbacks: fenced code block containing a TLV header, or a bare reply
    # that IS the file (starts with the TLV version line).
    m = re.search(r"```[a-zA-Z]*\n(\\m[45]_?TLV_version.*?)```", text, re.S)
    if m:
        return m.group(1)
    t = text.strip()
    if t.startswith("\\m5_TLV_version") or t.startswith("\\m4_TLV_version") \
            or t.startswith("\\TLV_version"):
        return t
    return None


def main():
    # Agents must produce the TLV; never fall back to a stale Verilog file.
    sv = os.path.join(ROOT, "hw/scorer.v")
    if os.path.exists(sv):
        os.remove(sv)

    providers = [tuple(x.split(":")) for x in
                 os.environ.get("MM_PROVIDERS", "deepseek:5,claude:6").split(",")]
    cost = {"deepseek": 0.0, "claude": 0.0}
    feedback = None
    attempts = []
    t0 = time.time()
    for provider, tries in [(p, int(n)) for p, n in providers]:
        for a in range(1, tries + 1):
            print(f"  [{provider} #{a}] goi API ...", flush=True)
            resp, i, o = call_retry(provider, build_user(feedback))
            c = (i*0.14 + o*0.28)/1e6 if provider == "deepseek" else (i*3.0 + o*15.0)/1e6
            cost[provider] += c
            if cost[provider] > MAX_COST[provider]:
                print(f"!!! COST CAP {provider}")
                break
            body = extract(resp)
            if body is None:
                print(f"  [{provider} #{a}] khong parse duoc (da log), retry")
                with open(os.path.join(ROOT, f"agentflow/unparsed_{provider}_{a}.txt"), "w") as f:
                    f.write(resp)
                feedback = ("Your reply did not follow the required format. Reply with "
                            "EXACTLY:\n===FILE: scorer.tlv===\n<file contents>\n===END===")
                attempts.append((provider, a, "unparsed", c))
                continue
            with open(os.path.join(ROOT, "hw/scorer.tlv"), "w") as f:
                f.write(body.rstrip() + "\n")
            ok, out = run_checks()
            tail = out.strip().splitlines()[-1] if out.strip() else ""
            print(f"  [{provider} #{a}] check={'PASS' if ok else 'FAIL'} (${c:.4f}) {tail}")
            attempts.append((provider, a, "PASS" if ok else "FAIL", c))
            # Save every attempt for the paper trail.
            with open(os.path.join(ROOT, f"agentflow/attempt_{provider}_{a}.tlv"), "w") as f:
                f.write(body)
            with open(os.path.join(ROOT, f"agentflow/attempt_{provider}_{a}.log"), "w") as f:
                f.write(out)
            if ok:
                print(f"\n===== THANH CONG: {provider} attempt {a} =====")
                print(f"cost: ds ${cost['deepseek']:.4f} + cl ${cost['claude']:.4f}")
                print(f"thoi gian: {(time.time()-t0)/60:.1f} phut")
                return 0
            feedback = enrich(out)
    print("\n===== HET BUDGET, CHUA PASS =====")
    for p, a, r, c in attempts:
        print(f"  {p} #{a}: {r} (${c:.4f})")
    print(f"cost: ds ${cost['deepseek']:.4f} + cl ${cost['claude']:.4f}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
