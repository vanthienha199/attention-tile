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
         // Command and data
         $cmd[1:0] = *uio_in[1:0];
         $data[7:0] = *ui_in;
         
         // Query buffer flops (8 separate, signed)
         $q0[7:0], $q1[7:0], $q2[7:0], $q3[7:0], $q4[7:0], $q5[7:0], $q6[7:0], $q7[7:0];
         <<1$q0 = *reset ? 8'd0 : (($cmd == 1) && ($q_waddr == 0) ? $data : $q0);
         <<1$q1 = *reset ? 8'd0 : (($cmd == 1) && ($q_waddr == 1) ? $data : $q1);
         <<1$q2 = *reset ? 8'd0 : (($cmd == 1) && ($q_waddr == 2) ? $data : $q2);
         <<1$q3 = *reset ? 8'd0 : (($cmd == 1) && ($q_waddr == 3) ? $data : $q3);
         <<1$q4 = *reset ? 8'd0 : (($cmd == 1) && ($q_waddr == 4) ? $data : $q4);
         <<1$q5 = *reset ? 8'd0 : (($cmd == 1) && ($q_waddr == 5) ? $data : $q5);
         <<1$q6 = *reset ? 8'd0 : (($cmd == 1) && ($q_waddr == 6) ? $data : $q6);
         <<1$q7 = *reset ? 8'd0 : (($cmd == 1) && ($q_waddr == 7) ? $data : $q7);
         
         // Query write address (use low 3 bits of qfill, works for qfill==8 as well)
         $q_waddr[2:0] = ($cmd == 1) ? $qfill[2:0] : 3'd0;
         
         // Query select mux
         $q_sel[7:0] = ($dim == 0) ? $q0 : ($dim == 1) ? $q1 : ($dim == 2) ? $q2 : ($dim == 3) ? $q3 : ($dim == 4) ? $q4 : ($dim == 5) ? $q5 : ($dim == 6) ? $q6 : $q7;
         
         // Product and accumulator with saturation
         $prod[15:0] = \$signed($q_sel) * \$signed($data);
         $acc_raw[15:0] = \$signed($acc) + \$signed($prod);
         $sat_high = (\$signed($acc_raw) > 32767);
         $sat_low  = (\$signed($acc_raw) < -32768);
         $sat_val[15:0] = $sat_high ? 16'sd32767 : ($sat_low ? 16'sd-32768 : $acc_raw);
         
         // Next state signals (combinational)
         // qfill next
         $next_qfill[3:0] = *reset ? 4'd0 :
                             ($cmd == 1) ? (($qfill == 4'd8) ? 4'd1 : $qfill + 1) :
                             (($cmd == 2) || ($cmd == 0)) ? (($qfill < 4'd8) ? 4'd0 : $qfill) :
                             $qfill; // READ
         
         // dim next
         $next_dim[2:0] = *reset ? 3'd0 :
                           (($cmd == 2) && !$key_idx[6]) ? (($dim == 3'd7) ? 3'd0 : $dim + 1) :
                           (($cmd == 1) || ($cmd == 0)) ? 3'd0 :
                           $dim;
         
         // acc next (account for key_idx overflow and key completion)
         $acc_accum[15:0] = (($cmd == 2) && !$key_idx[6]) ? (($dim == 7) ? 16'd0 : $sat_val) : 16'd0;
         $acc_reset = (($cmd == 1) || ($cmd == 0)) ? 16'd0 : 16'd0;
         $next_acc[15:0] = *reset ? 16'd0 :
                            ($cmd == 2) ? (($dim == 7) ? 16'd0 : $sat_val) : // key complete resets to 0
                            (($cmd == 1) || ($cmd == 0)) ? 16'd0 :
                            $acc; // READ
         
         // best next
         $best_update = ($cmd == 2) && ($dim == 7) && !$key_idx[6] && (\$signed($sat_val) > \$signed($best));
         $best_clear  = ($cmd == 1) && ($qfill == 4'd7);
         $next_best[15:0] = *reset ? 16'h8000 :
                             $best_update ? $sat_val :
                             $best_clear ? 16'h8000 :
                             $best;
         
         // best_idx next
         $next_best_idx[5:0] = *reset ? 6'd0 :
                                $best_update ? $key_idx[5:0] :
                                $best_clear ? 6'd0 :
                                $best_idx;
         
         // key_idx next (7-bit to track overflow beyond 63)
         $key_inc = ($cmd == 2) && ($dim == 7) && !$key_idx[6];
         $next_key_idx[6:0] = *reset ? 7'd0 :
                               ($cmd == 1) && ($qfill == 4'd7) ? 7'd0 : // new query resets key counter
                               $key_inc ? $key_idx + 7'd1 :
                               $key_idx;
         
         // read_phase next
         $next_read_phase[1:0] = *reset ? 2'd0 :
                                  ($cmd == 3) ? ($read_phase + 2'd1) : 2'd0;
         
         // Output combinational
         $out_computed[7:0] = ($cmd == 3) ?
                                (($read_phase == 0) ? {2'b00, $best_idx[5:0]} :
                                 ($read_phase == 1) ? $best[15:8] :
                                 $best[7:0]) :
                                $out_reg;
         
         // Flop updates
         <<1$qfill = $next_qfill;
         <<1$dim   = $next_dim;
         <<1$acc   = $next_acc;
         <<1$best  = $next_best;
         <<1$best_idx = $next_best_idx;
         <<1$key_idx  = $next_key_idx;
         <<1$read_phase = $next_read_phase;
         <<1$out_reg = *reset ? 8'd0 : (($cmd == 3) ? $out_computed : $out_reg);
         
         // Output assignment
         *uo_out = $out_computed;
         
\SV
   endmodule