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
         *uo_out = $out;   // driven from \SV_plus
\SV
   // All state and logic in \SV_plus
   reg [3:0] qfill;          // 0..8
   reg [2:0] dim;            // 0..7
   reg signed [15:0] acc;
   reg signed [15:0] best;   // initialized to -32768
   reg [5:0] best_idx;
   reg [5:0] key_idx;
   reg [1:0] read_phase;     // 0,1,2
   reg [7:0] out;
   reg [7:0] q_mem [0:7];

   wire [1:0] cmd = uio_in[1:0];
   wire [7:0] data = ui_in;

   // Helper: signed saturating addition
   function signed [15:0] sat16;
      input signed [15:0] a;
      input signed [15:0] b;
      reg signed [16:0] sum_ext;
      begin
         sum_ext = {a[15], a} + {b[15], b};
         if (sum_ext > 16'sd32767)
            sat16 = 16'sd32767;
         else if (sum_ext < -16'sd32768)
            sat16 = -16'sd32768;
         else
            sat16 = sum_ext[15:0];
      end
   endfunction

   always_ff @(posedge clk) begin
      if (reset) begin
         qfill <= 0;
         dim <= 0;
         acc <= 0;
         best <= -16'sd32768;
         best_idx <= 0;
         key_idx <= 0;
         read_phase <= 0;
         out <= 0;
         for (int i=0; i<8; i++) q_mem[i] <= 0;
      end else begin
         // Default values (most will be overridden)
         out <= out;  // hold
         read_phase <= 0;  // reset unless cmd=3
         acc <= 0;    // will be overridden for STREAM_K and IDLE? Actually IDLE also sets to 0, fine
         dim <= 0;    // will be overridden for STREAM_K only if not completing
         qfill <= qfill;
         best <= best;
         best_idx <= best_idx;
         key_idx <= key_idx;
         
         if (cmd == 1) begin // LOAD_Q
            // Interrupt partial key: reset acc and dim
            acc <= 0;
            dim <= 0;
            // Write byte to query buffer
            if (qfill >= 8) begin
               q_mem[0] <= data;
               qfill <= 1;  // after write, new qfill = 1
               // Check if completing query (wraparound): after write, qfill becomes 1, not 8, so no reset
            end else begin
               q_mem[qfill] <= data;
               qfill <= qfill + 1;
               // If after increment qfill becomes 8, reset best etc.
               if (qfill + 1 == 8) begin
                  best <= -16'sd32768;
                  best_idx <= 0;
                  key_idx <= 0;
               end
            end
         end else if (cmd == 2) begin // STREAM_K
            // If query not complete, reset qfill
            if (qfill < 8) qfill <= 0;
            // Process key only if key_idx <= 63
            if (key_idx <= 63) begin
               acc <= sat16(acc, $signed(q_mem[dim]) * $signed(data));
               dim <= dim + 1;
               // If completing key (dim was 7, after increment becomes 8)
               if (dim == 7) begin
                  // The next acc value has been computed above (using current acc)
                  // But we need the final acc after multiply-add. Since nonblocking, we need to compute separately.
                  // We'll compute final_acc combinational and use it.
                  // Actually we can compute in the always_ff using temporary.
               end
            end else begin
               // key_idx > 63: ignore
               acc <= acc;
               dim <= dim;
            end
         end else if (cmd == 3) begin // READ
            read_phase <= (read_phase == 2) ? 0 : read_phase + 1;
            case (read_phase)
               0: out <= {2'b00, best_idx};
               1: out <= best[15:8];
               2: out <= best[7:0];
               default: out <= out;
            endcase
            // acc and dim should remain unchanged? The golden does not modify them for READ
            // But we set acc<=0,dim<=0 above, need to preserve.
            acc <= acc;
            dim <= dim;
            qfill <= qfill;
         end else begin // IDLE (cmd==0)
            // Interrupt partial key: reset acc and dim
            acc <= 0;
            dim <= 0;
            // If query not complete, reset qfill
            if (qfill < 8) qfill <= 0;
            // best, key_idx unchanged
         end

         // For STREAM_K, we need to handle key completion after the multiply-add.
         // Since we have already scheduled acc with sat16, but we need the new acc to compare.
         // We'll move the complete-key logic after the acc assignment using the new value.
         // But nonblocking assignments make it impossible to read the newly computed acc in the same cycle.
         // We need to replicate the computation in the condition.
         // Alternatively, use a combinational variable for the next_acc and then use that.
         // Let's restructure the whole always_ff using temporary variables for all next states.
      end
   end

   // Because of the complexity with nonblocking assignments for the key completion,
   // we will use an intermediate combinational block to compute next states.
   // Actually, we can compute everything in a single always_ff with blocking assignments? No, that's not recommended.
   // Better to use a separate always_comb for next state and then flop.
   // We'll rewrite using pipesignals in TLV but that's what we wanted to avoid.
   // Given time, let's complete with the simple approach that matches the golden model closely.
   // The golden model's step() uses purely sequential logic: each cycle, it reads current state and writes next state.
   // In hardware, this is exactly what we want: registered state, combinational next.
   // We can do all combinational logic in \SV_plus using always_comb, then flop.
   // Let's adopt that approach.

   // Declare state as regs again but use always_comb for next state.
   // Actually we already have regs; we can compute next_* wires.

   // Let's rewrite from scratch in the \SV_plus block.

\SV_plus
   reg [3:0] qfill;
   reg [2:0] dim;
   reg signed [15:0] acc;
   reg signed [15:0] best;
   reg [5:0] best_idx;
   reg [5:0] key_idx;
   reg [1:0] read_phase;
   reg [7:0] out;
   reg [7:0] q_mem [0:7];

   wire [1:0] cmd = uio_in[1:0];
   wire [7:0] data = ui_in;

   // Next state combinational logic
   wire [3:0] next_qfill;
   wire [2:0] next_dim;
   wire signed [15:0] next_acc;
   wire signed [15:0] next_best;
   wire [5:0] next_best_idx;
   wire [5:0] next_key_idx;
   wire [1:0] next_read_phase;
   wire [7:0] next_out;
   // For q_mem, we need to update in combinational? Not possible; we'll do in always_ff.
   // So we'll keep the q_mem update in the always_ff and use the next_* for flops.

   always_comb begin
      // Default: hold
      next_qfill = qfill;
      next_dim = dim;
      next_acc = acc;
      next_best = best;
      next_best_idx = best_idx;
      next_key_idx = key_idx;
      next_read_phase = (cmd == 3) ? ((read_phase == 2) ? 0 : read_phase + 1) : 0;
      next_out = out;

      if (cmd == 1) begin // LOAD_Q
         next_acc = 0;
         next_dim = 0;
         if (qfill >= 8) next_qfill = 0;
         else next_qfill = qfill;
         // Write to q_mem will be done in always_ff using current qfill before increment.
         // But we need to know what to write: we'll handle in always_ff.
         // For now, compute next_qfill after increment:
         next_qfill = next_qfill + 1;
         if (next_qfill == 8) begin
            next_best = -16'sd32768;
            next_best_idx = 0;
            next_key_idx = 0;
         end
      end else if (cmd == 2) begin // STREAM_K
         if (qfill < 8) next_qfill = 0;  // interrupt partial query
         if (key_idx <= 63) begin
            // Compute product and saturate
            reg signed [15:0] product;
            product = $signed(q_mem[dim]) * $signed(data);
            next_acc = sat16(acc, product);
            next_dim = dim + 1;
            if (dim == 7) begin
               // Key complete
               if (next_acc > best) begin
                  next_best = next_acc;
                  next_best_idx = key_idx;
               end
               next_key_idx = key_idx + 1;
               next_acc = 0;
               next_dim = 0;
            end
         end
      end else if (cmd == 3) begin // READ
         next_acc = acc;
         next_dim = dim;
         next_qfill = qfill;
         case (read_phase)
            0: next_out = {2'b00, best_idx};
            1: next_out = best[15:8];
            2: next_out = best[7:0];
            default: next_out = out;
         endcase
      end else begin // IDLE (cmd==0)
         next_acc = 0;
         next_dim = 0;
         if (qfill < 8) next_qfill = 0;
      end
   end

   // Flop the next state
   always_ff @(posedge clk) begin
      if (reset) begin
         qfill <= 0;
         dim <= 0;
         acc <= 0;
         best <= -16'sd32768;
         best_idx <= 0;
         key_idx <= 0;
         read_phase <= 0;
         out <= 0;
         for (int i=0; i<8; i++) q_mem[i] <= 0;
      end else begin
         qfill <= next_qfill;
         dim <= next_dim;
         acc <= next_acc;
         best <= next_best;
         best_idx <= next_best_idx;
         key_idx <= next_key_idx;
         read_phase <= next_read_phase;
         out <= next_out;
         // Write query memory for LOAD_Q
         if (cmd == 1) begin
            // Use the current qfill (before increment) to write
            if (qfill >= 8) begin
               q_mem[0] <= data;
            end else begin
               q_mem[qfill] <= data;
            end
         end
      end
   end

   assign *uo_out = out;

\SV
   endmodule
\m5