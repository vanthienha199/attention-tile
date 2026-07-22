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
      @1
         $cmd[1:0]  = *uio_in[1:0];
         $data[7:0] = *ui_in;

         // Current state (flopped from previous cycle)
         // q0..q7, qfill, dim, acc, best, best_idx, key_idx, read_phase, out

         // Selected query element based on current dim
         $qsel[7:0] =
            ($dim[2:0] == 3'h0) ? $q0 :
            ($dim[2:0] == 3'h1) ? $q1 :
            ($dim[2:0] == 3'h2) ? $q2 :
            ($dim[2:0] == 3'h3) ? $q3 :
            ($dim[2:0] == 3'h4) ? $q4 :
            ($dim[2:0] == 3'h5) ? $q5 :
            ($dim[2:0] == 3'h6) ? $q6 :
                                  $q7;

         // Multiply (int8 x int8 -> int16) and saturating add
         $prod[15:0] = \$signed($qsel[7:0]) * \$signed($data[7:0]);
         $sum_full[16:0] = {$acc[15], $acc[15:0]} + {$prod[15], $prod[15:0]};
         $sat_sum[15:0] =
            ($sum_full[16:15] == 2'b01) ? 16'h7FFF :
            ($sum_full[16:15] == 2'b10) ? 16'h8000 :
            $sum_full[15:0];

         // Conditions
         $is_stream_k   = ($cmd == 2'h2);
         $q_complete    = ($qfill[3:0] == 4'h8);
         $key_in_range  = ($key_idx[6:0] <= 7'h3F);
         $do_accumulate = $is_stream_k && $q_complete && $key_in_range;
         $dim_complete  = ($dim[2:0] == 3'h7);
         $key_done      = $do_accumulate && $dim_complete;
         $new_is_better = \$signed($sat_sum) > \$signed($best[15:0]);

         // Write index for LOAD_Q
         $wr_idx[2:0] = ($qfill[3:0] == 4'h8) ? 3'h0 : $qfill[2:0];

         // Next qfill
         $qfill_nxt[3:0] =
            ($cmd == 2'h1) ?
               (($qfill == 4'h8) ? 4'h1 : $qfill + 4'h1) :
            (($cmd == 2'h2) || ($cmd == 2'h0)) ?
               (($qfill < 4'h8) ? 4'h0 : $qfill) :
            $qfill;

         // Next dim
         $dim_nxt[2:0] =
            ($cmd == 2'h1) ? 3'h0 :
            ($cmd == 2'h0) ? 3'h0 :
            $do_accumulate ?
               ($dim_complete ? 3'h0 : $dim + 3'h1) :
            $dim;

         // Next acc
         $acc_nxt[15:0] =
            (($cmd == 2'h1) || ($cmd == 2'h0)) ? 16'h0000 :
            $do_accumulate ?
               ($dim_complete ? 16'h0000 : $sat_sum) :
            $acc;

         // Next best (set to -32768 when 8th LOAD_Q byte arrives, i.e. qfill==7 going to 8)
         $best_nxt[15:0] =
            ($cmd == 2'h1 && $qfill == 4'h7) ? 16'h8000 :
            ($key_done && $new_is_better) ? $sat_sum :
            $best;

         // Next best_idx
         $best_idx_nxt[5:0] =
            ($cmd == 2'h1 && $qfill == 4'h7) ? 6'h00 :
            ($key_done && $new_is_better) ? $key_idx[5:0] :
            $best_idx;

         // Next key_idx
         $key_idx_nxt[6:0] =
            ($cmd == 2'h1 && $qfill == 4'h7) ? 7'h00 :
            ($key_done) ? $key_idx + 7'h01 :
            $key_idx;

         // Next read_phase
         $read_phase_nxt[1:0] =
            ($cmd == 2'h3) ?
               ($read_phase == 2'h2 ? 2'h0 : $read_phase + 2'h1) :
            2'h0;

         // Next out
         $out_nxt[7:0] =
            ($cmd == 2'h3) ?
               (($read_phase == 2'h0) ? {2'b00, $best_idx[5:0]} :
                ($read_phase == 2'h1) ? $best[15:8] :
                                        $best[7:0]) :
            $out;

         // Flopped state - next cycle assignments
         <<1$q0[7:0]         = *reset ? 8'h00 : ($cmd == 2'h1 && $wr_idx == 3'h0) ? $data : $q0;
         <<1$q1[7:0]         = *reset ? 8'h00 : ($cmd == 2'h1 && $wr_idx == 3'h1) ? $data : $q1;
         <<1$q2[7:0]         = *reset ? 8'h00 : ($cmd == 2'h1 && $wr_idx == 3'h2) ? $data : $q2;
         <<1$q3[7:0]         = *reset ? 8'h00 : ($cmd == 2'h1 && $wr_idx == 3'h3) ? $data : $q3;
         <<1$q4[7:0]         = *reset ? 8'h00 : ($cmd == 2'h1 && $wr_idx == 3'h4) ? $data : $q4;
         <<1$q5[7:0]         = *reset ? 8'h00 : ($cmd == 2'h1 && $wr_idx == 3'h5) ? $data : $q5;
         <<1$q6[7:0]         = *reset ? 8'h00 : ($cmd == 2'h1 && $wr_idx == 3'h6) ? $data : $q6;
         <<1$q7[7:0]         = *reset ? 8'h00 : ($cmd == 2'h1 && $wr_idx == 3'h7) ? $data : $q7;
         <<1$qfill[3:0]      = *reset ? 4'h0     : $qfill_nxt;
         <<1$dim[2:0]        = *reset ? 3'h0     : $dim_nxt;
         <<1$acc[15:0]       = *reset ? 16'h0000 : $acc_nxt;
         <<1$best[15:0]      = *reset ? 16'h8000 : $best_nxt;
         <<1$best_idx[5:0]   = *reset ? 6'h00    : $best_idx_nxt;
         <<1$key_idx[6:0]    = *reset ? 7'h00    : $key_idx_nxt;
         <<1$read_phase[1:0] = *reset ? 2'h0     : $read_phase_nxt;
         <<1$out[7:0]        = *reset ? 8'h00    : $out_nxt;

         *uo_out = $out;
\SV
   endmodule