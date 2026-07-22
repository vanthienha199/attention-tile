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
\SV_plus
   // saturating add for int16
   function automatic [15:0] sat_add_16(input signed [15:0] a, input signed [15:0] b);
      reg signed [16:0] sum;
      sum = a + b;
      if (sum > 32767) sat_add_16 = 32767;
      else if (sum < -32768) sat_add_16 = -32768;
      else sat_add_16 = sum[15:0];
   endfunction
\SV
\TLV
   |scorer
      @0
         // Inputs and reset
         $cmd[1:0] = *uio_in[1:0];
         $data[7:0] = *ui_in;
         $reset = *reset;

         // Query buffer as 8 separate 8-bit registers
         <<1$q0[7:0] = $reset ? 8'd0 : ($cmd==1 && ($idx_load==0)) ? $data : $q0;
         <<1$q1[7:0] = $reset ? 8'd0 : ($cmd==1 && ($idx_load==1)) ? $data : $q1;
         <<1$q2[7:0] = $reset ? 8'd0 : ($cmd==1 && ($idx_load==2)) ? $data : $q2;
         <<1$q3[7:0] = $reset ? 8'd0 : ($cmd==1 && ($idx_load==3)) ? $data : $q3;
         <<1$q4[7:0] = $reset ? 8'd0 : ($cmd==1 && ($idx_load==4)) ? $data : $q4;
         <<1$q5[7:0] = $reset ? 8'd0 : ($cmd==1 && ($idx_load==5)) ? $data : $q5;
         <<1$q6[7:0] = $reset ? 8'd0 : ($cmd==1 && ($idx_load==6)) ? $data : $q6;
         <<1$q7[7:0] = $reset ? 8'd0 : ($cmd==1 && ($idx_load==7)) ? $data : $q7;

         // Load index for query fill
         $idx_load[2:0] = ($qfill > 7) ? 3'd0 : $qfill[2:0];
         $qsel[7:0] = ($dim==0) ? $q0 :
                      ($dim==1) ? $q1 :
                      ($dim==2) ? $q2 :
                      ($dim==3) ? $q3 :
                      ($dim==4) ? $q4 :
                      ($dim==5) ? $q5 :
                      ($dim==6) ? $q6 : $q7;

         // Query fill counter (0..8)
         <<1$qfill[3:0] = $reset ? 4'd0 :
                          ($cmd==1) ? (($qfill >= 8) ? 4'd1 : $qfill + 4'd1) :
                          ($qfill < 8) ? 4'd0 : $qfill; // stay at 8 if complete

         // Key index counter (7 bits to allow 64 keys)
         <<1$key_idx[6:0] = $reset ? 7'd0 :
                            ($cmd==1 && ($qfill == 7)) ? 7'd0 : // load complete, reset key index
                            (($cmd==2) && ($qfill >= 8) && ($key_idx <= 63) && ($dim == 7)) ? $key_idx + 7'd1 : $key_idx;

         // Valid key condition
         $valid_key = ($cmd==2) && ($qfill >= 8) && ($key_idx <= 63);

         // Dimension counter (0..7)
         <<1$dim[2:0] = $reset ? 3'd0 :
                        ($cmd==1 || $cmd==0 || $cmd==3) ? 3'd0 :
                        ($valid_key) ? (($dim == 7) ? 3'd0 : $dim + 3'd1) : $dim;

         // Accumulator (int16)
         $prod[15:0] = $signed($qsel) * $signed($data);
         // Compute next accumulator using the saturating function (via SV function)
         $acc_next[15:0] = sat_add_16($signed($acc), $signed($prod));
         <<1$acc[15:0] = $reset ? 16'd0 :
                         ($cmd==1 || $cmd==0 || $cmd==3) ? 16'd0 :
                         ($valid_key) ? $acc_next : $acc;

         // Best score (int16) and index (6 bits)
         <<1$best[15:0] = $reset ? 16'd-32768 :
                          ($cmd==1 && ($qfill == 7)) ? 16'd-32768 :
                          ($valid_key && ($dim == 7) && ($acc_next > $best)) ? $acc_next : $best;
         <<1$best_idx[5:0] = $reset ? 6'd0 :
                             ($cmd==1 && ($qfill == 7)) ? 6'd0 :
                             ($valid_key && ($dim == 7) && ($acc_next > $best)) ? $key_idx[5:0] : $best_idx;

         // Read phase (0,1,2, wraps)
         <<1$read_phase[1:0] = $reset ? 2'd0 :
                               ($cmd==3) ? (($read_phase == 2) ? 2'd0 : $read_phase + 2'd1) : 2'd0;

         // Output byte
         $out_comb[7:0] = ($cmd==3) ? (($read_phase==0) ? $best_idx[5:0] : (($read_phase==1) ? $best[15:8] : $best[7:0])) : $out;
         <<1$out[7:0] = $reset ? 8'd0 : $out_comb;

         // Connect to module output
         *uo_out = $out;
\SV
   endmodule