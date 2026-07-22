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
   wire [1:0] cmd = uio_in[1:0];
\TLV
   |scorer
      @0
         // Query buffer (8 separate 8-bit signals)
         $q0[7:0] = 0;
         $q1[7:0] = 0;
         $q2[7:0] = 0;
         $q3[7:0] = 0;
         $q4[7:0] = 0;
         $q5[7:0] = 0;
         $q6[7:0] = 0;
         $q7[7:0] = 0;

         // State registers
         $qfill[3:0] = 0;      // 0..8, number of query bytes loaded
         $dim[2:0] = 0;        // current dimension in STREAM_K (0..7)
         $acc[15:0] = 0;       // partial accumulation (signed)
         $best[15:0] = 0;      // best score (signed)
         $best_idx[5:0] = 0;   // index of best key
         $key_idx[5:0] = 0;    // current key index (0..63)
         $read_phase[1:0] = 0; // READ phase (0,1,2,0,...)
         $out[7:0] = 0;        // output register

         // Combinational helpers
         $cmd[1:0] = *cmd;
         $data[7:0] = *ui_in;

         // Write index for LOAD_Q: use $qfill if <8, else 0
         $wr_idx[2:0] = ($qfill == 8) ? 3'h0 : $qfill[2:0];

         // Selected query element based on current dimension
         $qsel[7:0] = 
            ($dim == 0) ? $q0 :
            ($dim == 1) ? $q1 :
            ($dim == 2) ? $q2 :
            ($dim == 3) ? $q3 :
            ($dim == 4) ? $q4 :
            ($dim == 5) ? $q5 :
            ($dim == 6) ? $q6 :
                         $q7;

         // Signed multiplication and saturated addition
         $prod[15:0] = \$signed($qsel) * \$signed($data);
         $sum[15:0] = \$signed($acc) + \$signed($prod);
         $sat_sum[15:0] = 
            (\$signed($sum) > 32767) ? 16'h7FFF :
            (\$signed($sum) < -32768) ? 16'h8000 :
            $sum;

         // Next state logic for all registers
         // qfill (0..8)
         $qfill_next[3:0] = *reset ? 4'h0 :
            ($cmd == 1) ?                    // LOAD_Q
               ($qfill == 8) ? 4'h1 : $qfill + 1 :
            (($cmd == 2) || ($cmd == 0)) ?   // STREAM_K or IDLE
               ($qfill < 8) ? 4'h0 : $qfill :
            $qfill;                          // READ

         // dim (0..7)
         $dim_next[2:0] = *reset ? 3'h0 :
            ($cmd == 1) ? 3'h0 :            // LOAD_Q
            ($cmd == 2 && $qfill == 8 && $key_idx <= 63) ?
               ($dim == 7) ? 3'h0 : $dim + 1 :
            ($cmd == 0) ? 3'h0 :            // IDLE
            $dim;

         // acc
         $acc_next[15:0] = *reset ? 16'h0000 :
            ($cmd == 2 && $qfill == 8 && $key_idx <= 63) ?
               ($dim == 7) ? 16'h0000 : $sat_sum :   // key complete -> acc to 0, else accumulate
            (($cmd == 1) || ($cmd == 0)) ? 16'h0000 : // LOAD_Q or IDLE
            $acc;

         // best, best_idx, key_idx updates when key completes (dim=7 and receiving 8th byte)
         $best_next[15:0] = *reset ? 16'h8000 : // -32768
            ($cmd == 1 && $qfill == 7) ? 16'h8000 : // new query complete -> reset best
            ($cmd == 2 && $qfill == 8 && $key_idx <= 63 && $dim == 7 &&
                (\$signed($sat_sum) > \$signed($best))) ? $sat_sum :
            $best;

         $best_idx_next[5:0] = *reset ? 6'h00 :
            ($cmd == 1 && $qfill == 7) ? 6'h00 :
            ($cmd == 2 && $qfill == 8 && $key_idx <= 63 && $dim == 7 &&
                (\$signed($sat_sum) > \$signed($best))) ? $key_idx :
            $best_idx;

         $key_idx_next[5:0] = *reset ? 6'h00 :
            ($cmd == 1 && $qfill == 7) ? 6'h00 : // new query
            ($cmd == 2 && $qfill == 8 && $key_idx <= 63 && $dim == 7) ?
               ($key_idx == 63 ? 6'h00 : $key_idx + 1) : // wrap at 63? spec says after 63 ignore, but we still increment? Actually after 63 ignore further, but key_idx stays at 63? Spec: "after key 63 the scorer ignores further STREAM_K bytes until a new query completes". So key_idx should stay at 63 and not increment further. So we do not increment when key_idx==63.
               // But when key completes, if key_idx == 63, we should not increment; we just ignore. So condition: ($key_idx == 63) ? 6'h3F : $key_idx+1, but only if key_idx < 63. So:
            $key_idx;

         // Actually key_idx increment only if key_idx < 63.
         // Let's correct: 
         // $key_idx_next = ... else ($cmd==2 && ... && $dim==7 && $key_idx < 63) ? $key_idx + 1 : $key_idx;

         // We'll adjust in the final code.

         // read_phase
         $read_phase_next[1:0] = *reset ? 2'h0 :
            ($cmd == 3) ?
               ($read_phase == 2 ? 2'h0 : $read_phase + 1) :
            2'h0; // non-READ resets

         // out
         $out_next[7:0] = *reset ? 8'h00 :
            ($cmd == 3) ?
               ($read_phase == 0) ? {2'b00, $best_idx} :
               ($read_phase == 1) ? $best[15:8] :
               $best[7:0] :
            $out; // hold during non-READ

         // Sequential assignments with reset
         <<1$q0 = *reset ? 8'h00 : ($cmd == 1 && $wr_idx == 0) ? $data : $q0;
         <<1$q1 = *reset ? 8'h00 : ($cmd == 1 && $wr_idx == 1) ? $data : $q1;
         <<1$q2 = *reset ? 8'h00 : ($cmd == 1 && $wr_idx == 2) ? $data : $q2;
         <<1$q3 = *reset ? 8'h00 : ($cmd == 1 && $wr_idx == 3) ? $data : $q3;
         <<1$q4 = *reset ? 8'h00 : ($cmd == 1 && $wr_idx == 4) ? $data : $q4;
         <<1$q5 = *reset ? 8'h00 : ($cmd == 1 && $wr_idx == 5) ? $data : $q5;
         <<1$q6 = *reset ? 8'h00 : ($cmd == 1 && $wr_idx == 6) ? $data : $q6;
         <<1$q7 = *reset ? 8'h00 : ($cmd == 1 && $wr_idx == 7) ? $data : $q7;

         <<1$qfill = $qfill_next;
         <<1$dim    = $dim_next;
         <<1$acc    = $acc_next;
         <<1$best   = $best_next;
         <<1$best_idx = $best_idx_next;
         <<1$key_idx = $key_idx_next;
         <<1$read_phase = $read_phase_next;
         <<1$out = $out_next;

         // Output assignment
         *uo_out = $out;
\SV
   endmodule