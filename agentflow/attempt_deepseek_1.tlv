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
         $cmd[1:0] = *uio_in[1:0];
         $data[7:0] = *ui_in[7:0];
         // Query buffer mux
         $qsel[7:0] = ($dim == 0) ? $q0 :
                      ($dim == 1) ? $q1 :
                      ($dim == 2) ? $q2 :
                      ($dim == 3) ? $q3 :
                      ($dim == 4) ? $q4 :
                      ($dim == 5) ? $q5 :
                      ($dim == 6) ? $q6 : $q7;
         // Product and sum
         $prod[15:0] = \$signed($qsel) * \$signed($data);
         $sum[16:0] = \$signed($acc) + \$signed($prod);
         // Saturate to 16 bits
         $sat_high = ($sum > 17'd32767);
         $sat_low  = ($sum < -17'd32768);
         $final_acc[15:0] = $sat_high ? 16'd32767 : ($sat_low ? -16'd32768 : $sum[15:0]);
         // Key complete detection
         $key_done = ($cmd == 2) && ($dim == 7) && ($key_idx <= 63);
         // Accumulation enable (ignored if key_idx > 63)
         $acc_enable = ($cmd == 2) && ($key_idx <= 63);
         // Next counters
         $nqfill[3:0] = *reset ? 0 :
                        ($cmd == 1) ? (($qfill == 8) ? 1 : $qfill + 1) :
                        ((($cmd == 0) || ($cmd == 2)) && ($qfill < 8) ? 0 : $qfill);
         $ndim[3:0] = *reset ? 0 :
                      (($cmd == 0) || ($cmd == 1)) ? 0 :
                      ($acc_enable ? (($dim == 7) ? 0 : $dim + 1) : $dim);
         $nacc[15:0] = *reset ? 0 :
                       (($cmd == 0) || ($cmd == 1)) ? 0 :
                       ($acc_enable ? $final_acc : $acc);
         // Best score and index
         $nbest[15:0] = *reset ? -16'd32768 :
                        ($key_done && ($final_acc > \$signed($best)) ? $final_acc : $best);
         $nbest_idx[5:0] = *reset ? 0 :
                           ($key_done && ($final_acc > \$signed($best)) ? $key_idx[5:0] : $best_idx);
         // Key index
         $nkey_idx[6:0] = *reset ? 0 :
                          ($key_done ? ($key_idx + 1) : $key_idx);
         // Read phase
         $nrp[1:0] = *reset ? 0 :
                     (($cmd == 3) ? (($rp == 2) ? 0 : $rp + 1) : 0);
         // Output byte
         $read_data[7:0] = ($rp == 0) ? $best_idx[5:0] :
                           (($rp == 1) ? $best[15:8] : $best[7:0]);
         $nout[7:0] = *reset ? 0 :
                      (($cmd == 3) ? $read_data : $out_reg);
         // Query buffer writes
         $wq = ($cmd == 1);
         $nq0[7:0] = *reset ? 0 : ($wq && ($qfill == 0) ? $data : $q0);
         $nq1[7:0] = *reset ? 0 : ($wq && ($qfill == 1) ? $data : $q1);
         $nq2[7:0] = *reset ? 0 : ($wq && ($qfill == 2) ? $data : $q2);
         $nq3[7:0] = *reset ? 0 : ($wq && ($qfill == 3) ? $data : $q3);
         $nq4[7:0] = *reset ? 0 : ($wq && ($qfill == 4) ? $data : $q4);
         $nq5[7:0] = *reset ? 0 : ($wq && ($qfill == 5) ? $data : $q5);
         $nq6[7:0] = *reset ? 0 : ($wq && ($qfill == 6) ? $data : $q6);
         $nq7[7:0] = *reset ? 0 : ($wq && ($qfill == 7) ? $data : $q7);
         // Flop updates
         <<1$q0 = $nq0;
         <<1$q1 = $nq1;
         <<1$q2 = $nq2;
         <<1$q3 = $nq3;
         <<1$q4 = $nq4;
         <<1$q5 = $nq5;
         <<1$q6 = $nq6;
         <<1$q7 = $nq7;
         <<1$qfill = $nqfill;
         <<1$dim = $ndim;
         <<1$acc = $nacc;
         <<1$best = $nbest;
         <<1$best_idx = $nbest_idx;
         <<1$key_idx = $nkey_idx;
         <<1$rp = $nrp;
         <<1$out_reg = $nout;
         *uo_out = $out_reg;
\SV
   endmodule