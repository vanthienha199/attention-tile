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
   // Declare combinational wires for command and data
   wire [1:0] cmd = uio_in[1:0];
   wire [7:0] data = ui_in;
\TLV
   |scorer
      @0
         // State registers (flops)
         // Query buffer: 8 separate 8-bit signals
         $q0[7:0] = *data; // placeholder, actual assignment below
         $q1[7:0] = *data;
         $q2[7:0] = *data;
         $q3[7:0] = *data;
         $q4[7:0] = *data;
         $q5[7:0] = *data;
         $q6[7:0] = *data;
         $q7[7:0] = *data;
         // Control and status
         $qfill[3:0] = 0; // 0..8, but we need 4 bits
         $dim[3:0] = 0;
         $acc[15:0] = 0;
         $best[15:0] = 0;
         $best_idx[5:0] = 0;
         $key_idx[6:0] = 0; // 0..63, need 7 bits to hold 63
         $read_phase[2:0] = 0;
         $out[7:0] = 0;
         
         // Next state logic for each register
         // We'll use a single always block style with @0 assignments and pipelines
         
         // Decode command
         $cmd[1:0] = *cmd;
         $data[7:0] = *data;
         
         // Command type constants for readability (not needed but helpful)
         // 0: IDLE, 1: LOAD_Q, 2: STREAM_K, 3: READ
         
         // Common logic: reset read_phase if not READ
         $reset_phase = ($cmd != 3) ? 1 : 0;
         
         // LOAD_Q logic
         $load_q = ($cmd == 1);
         // STREAM_K logic
         $stream_k = ($cmd == 2);
         // READ logic
         $read = ($cmd == 3);
         // IDLE or other
         $idle = ($cmd == 0);
         
         // Query fill pointer update
         // If load_q and qfill < 8, increment; if load_q and qfill >=8, reset to 1 (first byte of new query)
         $next_qfill[3:0] = 0;
         $qfill_inc = $load_q ? 1 : 0;
         $qfill_reset_to_1 = ($load_q && ($qfill == 8)) ? 1 : 0;
         $qfill_reset_to_0 = ($idle || ($stream_k && ($qfill < 8)) || ($load_q && ($qfill < 8) && ($qfill == 0 && !$load_first_byte?))) ? 1 : 0; // Actually handle carefully
         // Simpler: follow golden model exactly
         
         // We'll compute next_qfill in a separate section
         
         // Dimension counter
         // On stream_k and dim < 8: increment dim; on stream_k and dim == 8: dim stays? Actually after 8 dim resets to 0, but we handle that.
         // On any non-STREAM_K or interrupt (including load_q or idle) : dim = 0
         $dim_reset = ($stream_k && ($dim == 8)) ? 0 : ($load_q || $idle) ? 1 : 0;
         $dim_inc = $stream_k ? 1 : 0;
         
         // Accumulator
         // On stream_k: acc = sat16(acc + q[dim] * data) unless dim >= 8? Actually only if dim < 8.
         // On load_q, idle: acc = 0
         // On read: acc unchanged
         // On stream_k when dim == 8? That shouldn't happen because dim wraps.
         // We'll compute new_acc.
         
         // Best and best_idx update on key completion
         // When stream_k and next dim would be 8 after increment? Actually check dim == 7 and stream_k.
         $key_complete = ($stream_k && ($dim == 7));
         
         // Key index increment on key completion
         // Also key_idx restarted on load_q completion (qfill becomes 8)
         $key_idx_inc = $key_complete ? 1 : 0;
         $key_idx_reset = ($load_q && ($qfill == 7)) ? 1 : 0; // only when query just completed
         
         // Read phase
         $read_phase_next[2:0] = 0;
         $read_phase_reset = ($cmd != 3) ? 1 : 0;
         $read_phase_inc = $read ? 1 : 0;
         
         // Output assignment
         // For READ: based on read_phase % 3
         // For others: hold $out
         
         // ------------------------ Implementation of flops ------------------------
         // We will use <<1 to assign next values.
         // All state flops are declared with default 0 and reset.
         
         // Query buffer: we need to update only the byte corresponding to qfill when load_q.
         // Use a case or if-else on qfill, but since we can't index arrays, we'll assign each q individually.
         // To avoid combinatorial loops, we'll compute the new q value for each index.
         // We'll also need to handle reset: all q become 0.
         // Easiest: use a for loop in \SV_plus? But we want TL-Verilog style.
         // Since D=8 small, we can just write 8 conditional statements.
         
         // For each q index, if load_q and qfill == index, then load data, else hold.
         // Also reset to 0 on *reset.
         // Also if load_q and qfill >= 8, we treat as new query: qfill resets to 0 first then load.
         // Actually careful: qfill increments after loading. So the byte is stored at current qfill before increment.
         // In golden model: self.q[self.qfill] = to_s8(data); then qfill += 1.
         // So we load at current qfill.
         
         // We'll compute a 3-bit index (qfill[2:0]) for selection.
         $qf_addr[2:0] = $qfill[2:0];
         
         // For each q, its next value:
         // Reset: $q0_next = *reset ? 8'd0 : ($load_q && ($qf_addr == 0)) ? $data : $q0;
         // But we must ensure $data is signed? We'll use unsigned and treat as s8 in multiplication.
         // We'll keep raw bytes.
         
         // Let's assign flops individually.
         // Reset: all zero.
         // Otherwise, if load_q and address matches this index, load data.
         // Else hold.
         
         // However, we have to be careful about when qfill updates. We need to read current qfill, then after flop update, qfill changes.
         // Using pipelining: at @0, all combinational reads are current values. So we can use current qfill to decide which q to update.
         
         // For each q:
         // Use a macro? We'll write out 8 assignments.
         
         // Let's start writing the @0 pipe.
         
         // First, compute all combinational values.
         
         // qfill next:
         // reset: 0
         // load_q and qfill < 8: qfill + 1
         // load_q and qfill >= 8: 1 (since we start filling new query at index 0? Wait: golden model: if qfill >=8, set to 0. So after load of first byte of new query, qfill becomes 1. So next_qfill is 1.)
         // Actually: if qfill >= 8 and load_q, then qfill = 0 then increments to 1. So we should set next_qfill = 1.
         // In other cases: if not load_q, and not reset, hold.
         // But also: if idle or stream_k while qfill <8, reset qfill to 0 (golden: if cmd==0 or (cmd==2 and qfill<8) -> qfill=0)
         // And if stream_k and qfill >=8, qfill unchanged.
         // And if read, qfill unchanged.
         
         // So we need a complex FSM. Let's do it step by step.
         
         // We'll compute next_qfill as:
         // reset: 0
         // else if (load_q):
         //    if (qfill < 8) : qfill+1
         //    else : 1  (since qfill becomes 1 after first byte of new query)
         // else if (idle): 0
         // else if (stream_k && qfill < 8): 0
         // else: qfill (hold)
         
         // Similarly for dim:
         // reset: 0
         // else if (stream_k):
         //    if (dim < 8): dim+1
         //    else: 0 (dim goes to 0 after 8, but then next byte would be dim=0 again; we handle wrap)
         // else if (load_q || idle): 0
         // else: dim (hold)
         // But note: when dim = 8, it means we just completed a key? Actually dim goes 0..7, after increment from 7 it becomes 8, then on next clock we set dim to 0? No, we need to reset dim to 0 on the same cycle that we detected dim==7? In golden: after completing key, dim is set to 0. So if dim==7 and stream_k, next dim = 0 (since after increment dim would be 8, but we set to 0). Actually: after 8th byte, dim becomes 8, then later reset to 0? No, the key completion happens when dim == 7 (before increment) and after increment dim becomes 8? Let's check golden: self.dim += 1 after accumulate. Then if self.dim == 8: do key completion and set dim=0. So on the cycle after the 8th byte, dim becomes 8 and then we do the completion and set dim=0. But in our hardware, we should detect that dim is 7 and stream_k, and set next dim to 0 (not 8). So we skip the intermediate dim value of 8. This matches typical implementation. So:
         // Stream_k: if dim < 7: next dim = dim+1; if dim == 7: next dim = 0; if dim >= 8: shouldn't happen but keep 0.
         
         // For accumulator:
         // reset: 0
         // else if (stream_k && dim < 8): acc = sat16(acc + q[dim]*data)
         // else if (stream_k && dim == 7? Actually after accumulate, dim becomes 0, so acc is reset to 0 after key completion. So we need to handle two cases: dim < 7 -> update acc, dim == 7 -> update acc then next acc = 0 (but we update acc on same cycle? Golden: on 8th byte, acc is updated with product, then immediately after key completion, acc is set to 0. So we need to compute the new accumulator as the saturated value, but then if key completes, next acc is 0. So we can compute a temporary new acc and then override with 0 if key completes.
         // Actually: on STREAM_K, acc = sat16(acc + q_dim * data). Then if dim == 7 (meaning this was the 8th dimension), after this, we set acc = 0. So the flop stores 0 after the cycle. So we can compute next_acc as:
         // If stream_k: tmp = sat16(acc + product); if dim == 7: next_acc = 0 else next_acc = tmp.
         // If load_q or idle: next_acc = 0.
         // else: hold.
         
         // For best and best_idx:
         // reset: best = -32768, best_idx = 0
         // else if key_complete (dim==7 and stream_k) and acc > best: best = new_acc, best_idx = key_idx
         // else: hold.
         // Note: we need to compare the updated accumulator (after adding the product) with current best. The golden: after completing key, if self.acc > self.best then update. The self.acc used is after the final accumulation. So we need to use the new_acc value (before reset to 0) for comparison. That is, we compute tmp = sat16(acc + product). If dim==7 and tmp > best: set best = tmp and best_idx = key_idx.
         
         // For key_idx:
         // reset: 0
         // else if key_complete: key_idx + 1
         // else if load_q completion (qfill == 7 and load_q): key_idx = 0  (actually golden: after loading 8th byte, key_idx = 0)
         // else: hold.
         
         // For read_phase:
         // reset: 0
         // else if read: read_phase+1 (mod 3? Actually golden counts up unbounded but we only need mod 3)
         // else if not read: 0
         
         // For out:
         // reset: 0
         // else if read: based on read_phase
         // else: hold (last value)
         
         // We'll implement using <<1 assignments.
         // Since we have many conditions, we can write multiple @0 pipelines with careful ordering.
         // But simpler: we can use a single @0 block and assign each next state using conditions.
         
         // Let's declare intermediate signals.
         $product[15:0] = \$signed($qsel) * \$signed($data);
         // But we need qsel which is the query value for current dim.
         // Query selector: choose among q0..q7 based on dim.
         $qsel[7:0] = 0;
         // We'll assign qsel using a case: always @* combinational.
         // Since we can't use case in TL, we'll use ternary cascades.
         // But easier: we'll just compute all eight products and mux later? Too many.
         // Better: use \SV_plus to define a helper always_comb that assigns $qsel.
         
\SV_plus
         // We'll use Verilog for qsel mux to avoid TLV complexity.
         wire [7:0] qsel_comb;
         always @(*) begin
            case ($dim[2:0])
               3'd0: qsel_comb = $q0;
               3'd1: qsel_comb = $q1;
               3'd2: qsel_comb = $q2;
               3'd3: qsel_comb = $q3;
               3'd4: qsel_comb = $q4;
               3'd5: qsel_comb = $q5;
               3'd6: qsel_comb = $q6;
               3'd7: qsel_comb = $q7;
               default: qsel_comb = 8'd0;
            endcase
         end
         // Assign $qsel from the Verilog wire.
         // We need to access $dim, $q0..$q7 from TLV. Use backslash?
         // Actually in \SV_plus we can reference TLV pipe signals by their names prefixed with $$ (double dollar) or just $name? The doc says: In \SV_plus block, $$name refers to a pipe signal. So we use $$dim, $$q0, etc.
\SV
         // Actually better to put the qsel combinational logic directly in TLV using ternary.
         // Since D=8, we can write a series of ternary operators.
         // $qsel = ($dim==0) ? $q0 : ($dim==1) ? $q1 : ...;
         
         // Let's do that.
\TLV
         $qsel[7:0] = ($dim == 0) ? $q0 :
                      ($dim == 1) ? $q1 :
                      ($dim == 2) ? $q2 :
                      ($dim == 3) ? $q3 :
                      ($dim == 4) ? $q4 :
                      ($dim == 5) ? $q5 :
                      ($dim == 6) ? $q6 :
                      ($dim == 7) ? $q7 : 8'd0;
         
         // Now the combinational signals.
         
         // Compute next_qfill
         $next_qfill[3:0] = *reset ? 4'd0 :
                           ($load_q) ? (($qfill < 8) ? ($qfill + 4'd1) : 4'd1) :
                           ($idle || ($stream_k && ($qfill < 8))) ? 4'd0 :
                           $qfill;
         
         // Compute next_dim
         $next_dim[3:0] = *reset ? 4'd0 :
                         ($stream_k) ? (($dim < 7) ? ($dim + 4'd1) : 4'd0) :
                         (($load_q || $idle) && !$read) ? 4'd0 :
                         $dim; // read case holds
         
         // Compute product and new_acc_temp
         $product[15:0] = \$signed($qsel) * \$signed($data);
         $new_acc_temp[15:0] = \$signed($acc) + \$signed($product);
         // Saturate
         $sat_new_acc[15:0] = ($new_acc_temp > 32767) ? 16'd32767 :
                             ($new_acc_temp < -32768) ? 16'd32768 : $new_acc_temp;
         // Note: two's complement for -32768 is 0x8000, but we need unsigned representation. In TL, numbers are unsigned, we use \$signed for comparison. Actually we can use: if ($new_acc_temp > 16'h7FFF) ... else if ($new_acc_temp < 16'h8000) ... but careful with signed.
         // Easiest: cast to signed for comparison in SV but in TLV we can use \$signed. Since we already have \$signed, we can do:
         // $gt = \$signed($new_acc_temp[15:0]) > \$signed(16'd32767);
         // Instead, we can compute using bit tricks, but simpler: use an always_comb in \SV_plus for saturation.
         // Let's use \SV_plus for saturating addition to avoid TLV complexity.
\SV_plus
         // Saturation logic using Verilog
         wire signed [15:0] acc_s = \$signed($acc);
         wire signed [15:0] prod_s = \$signed($qsel) * \$signed($data);
         wire signed [16:0] sum_s = acc_s + prod_s; // 17 bits
         wire signed [15:0] sat_sum;
         always @(*) begin
            if (sum_s > 16'sd32767)
               sat_sum = 16'sd32767;
            else if (sum_s < -16'sd32768)
               sat_sum = -16'sd32768;
            else
               sat_sum = sum_s[15:0];
         end
         //assign to TLV signal $sat_new_acc
         // use double dollar for pipe signals in \SV_plus? Actually we need to assign to $sat_new_acc from Verilog.
         // We'll define a wire and then assign in TLV? Or we can assign directly with $$sat_new_acc = sat_sum; but need to be inside an always block. Let's do:
         // always @(*) $$sat_new_acc = sat_sum;
         // But that would be driving a wire from an always block? Better to use assign.
         assign $$sat_new_acc = sat_sum;
\TLV
         // Then use $sat_new_acc in TLV.
         
         // Now compute next_acc:
         $next_acc[15:0] = *reset ? 16'd0 :
                         ($stream_k) ? (($dim == 7) ? 16'd0 : $sat_new_acc) :
                         (($load_q || $idle) && !$read) ? 16'd0 :
                         $acc; // hold
         
         // Key completion flag
         $key_complete = ($stream_k && ($dim == 7));
         
         // Compare: if key_complete and $sat_new_acc > $best, then update best and best_idx.
         $gt[0:0] = (\$signed($sat_new_acc) > \$signed($best));
         $next_best[15:0] = *reset ? 16'd32768 : // -32768 in unsigned? Use 16'h8000.
                           ($key_complete && $gt) ? $sat_new_acc :
                           $best;
         $next_best_idx[5:0] = *reset ? 6'd0 :
                              ($key_complete && $gt) ? $key_idx[5:0] :
                              $best_idx;
         
         // Key index update
         $key_idx_next[6:0] = *reset ? 7'd0 :
                             ($key_complete) ? ($key_idx + 7'd1) :
                             (($load_q && ($qfill == 7)) ? 7'd0 :
                             $key_idx);
         // Note: $key_idx held during other commands
         
         // Read phase update
         $next_read_phase[2:0] = *reset ? 3'd0 :
                               ($read) ? (($read_phase == 3'd2) ? 3'd0 : ($read_phase + 3'd1)) :
                               3'd0;
         
         // Output for read
         $read_out[7:0] = ($read_phase == 0) ? {2'b00, $best_idx[5:0]} :
                         ($read_phase == 1) ? $best[15:8] :
                         $best[7:0];
         $next_out[7:0] = *reset ? 8'd0 :
                         ($read) ? $read_out :
                         $out;
         
         // Query buffer updates
         // For each q index i:
         // If *reset: next_q[i]=0
         // Else if load_q and qfill == i: next_q[i] = data
         // Else: next_q[i] = current q[i]
         // We'll use ternary for each.
         
         // Helper: $load_q_and_addr_eq = for each i, we can compute a signal.
         // Since i is constant, we can write out 8 cases.
         
         // For q0:
         $load_q_at_0 = ($load_q && ($qfill == 0));
         $q0_next[7:0] = *reset ? 8'd0 : ($load_q_at_0 ? $data : $q0);
         $q1_next[7:0] = *reset ? 8'd0 : (($load_q && ($qfill == 1)) ? $data : $q1);
         $q2_next[7:0] = *reset ? 8'd0 : (($load_q && ($qfill == 2)) ? $data : $q2);
         $q3_next[7:0] = *reset ? 8'd0 : (($load_q && ($qfill == 3)) ? $data : $q3);
         $q4_next[7:0] = *reset ? 8'd0 : (($load_q && ($qfill == 4)) ? $data : $q4);
         $q5_next[7:0] = *reset ? 8'd0 : (($load_q && ($qfill == 5)) ? $data : $q5);
         $q6_next[7:0] = *reset ? 8'd0 : (($load_q && ($qfill == 6)) ? $data : $q6);
         $q7_next[7:0] = *reset ? 8'd0 : (($load_q && ($qfill == 7)) ? $data : $q7);
         
         // Now assign next state flops using <<1.
         <<1$qfill = $next_qfill;
         <<1$dim = $next_dim;
         <<1$acc = $next_acc;
         <<1$best = $next_best;
         <<1$best_idx = $next_best_idx;
         <<1$key_idx = $key_idx_next;
         <<1$read_phase = $next_read_phase;
         <<1$out = $next_out;
         <<1$q0 = $q0_next;
         <<1$q1 = $q1_next;
         <<1$q2 = $q2_next;
         <<1$q3 = $q3_next;
         <<1$q4 = $q4_next;
         <<1$q5 = $q5_next;
         <<1$q6 = $q6_next;
         <<1$q7 = $q7_next;
         
         // Output assignment
         *uo_out = $out;
\SV
   endmodule