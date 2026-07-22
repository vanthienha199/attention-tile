// Hand-written reference implementation of the attention scorer (plain SV).
// Used to validate the verification harness before any generated design runs,
// and kept as the human baseline for comparison.
`default_nettype none

module tt_um_hale_attn_scorer (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);
  assign uio_out = 8'b0;
  assign uio_oe  = 8'b0;

  wire [1:0] cmd = uio_in[1:0];

  reg signed [7:0]  q [0:7];
  reg [3:0]         qfill;      // 0..8
  reg [2:0]         dim;        // 0..7
  reg signed [15:0] acc;
  reg signed [15:0] best;
  reg [5:0]         best_idx;
  reg [6:0]         key_idx;    // saturates at 64 (full)
  reg [1:0]         read_phase; // 0,1,2
  reg [7:0]         out_r;

  assign uo_out = out_r;

  wire signed [7:0]  kbyte = ui_in;
  wire signed [15:0] prod  = q[dim] * kbyte;
  wire signed [16:0] sum   = {acc[15], acc} + {prod[15], prod};
  wire signed [15:0] sum_sat = (sum > 17'sd32767)  ? 16'sd32767 :
                               (sum < -17'sd32768) ? -16'sd32768 :
                               sum[15:0];

  integer i;
  always @(posedge clk) begin
    if (!rst_n) begin
      for (i = 0; i < 8; i = i + 1) q[i] <= 8'sd0;
      qfill      <= 4'd0;
      dim        <= 3'd0;
      acc        <= 16'sd0;
      best       <= -16'sd32768;
      best_idx   <= 6'd0;
      key_idx    <= 7'd0;
      read_phase <= 2'd0;
      out_r      <= 8'd0;
    end else begin
      if (cmd != 2'd3)
        read_phase <= 2'd0;

      case (cmd)
        2'd1: begin // LOAD_Q
          acc <= 16'sd0;
          dim <= 3'd0;
          if (qfill >= 4'd8) begin
            q[0]  <= ui_in;
            qfill <= 4'd1;
          end else begin
            q[qfill[2:0]] <= ui_in;
            qfill <= qfill + 4'd1;
            if (qfill == 4'd7) begin
              best     <= -16'sd32768;
              best_idx <= 6'd0;
              key_idx  <= 7'd0;
            end
          end
        end
        2'd2: begin // STREAM_K
          if (qfill < 4'd8)
            qfill <= 4'd0;
          if (key_idx <= 7'd63) begin
            if (dim == 3'd7) begin
              if (sum_sat > best) begin
                best     <= sum_sat;
                best_idx <= key_idx[5:0];
              end
              key_idx <= key_idx + 7'd1;
              acc <= 16'sd0;
              dim <= 3'd0;
            end else begin
              acc <= sum_sat;
              dim <= dim + 3'd1;
            end
          end
        end
        2'd3: begin // READ
          case (read_phase)
            2'd0: out_r <= {2'b00, best_idx};
            2'd1: out_r <= best[15:8];
            default: out_r <= best[7:0];
          endcase
          read_phase <= (read_phase == 2'd2) ? 2'd0 : read_phase + 2'd1;
        end
        default: begin // IDLE
          acc <= 16'sd0;
          dim <= 3'd0;
          if (qfill < 4'd8)
            qfill <= 4'd0;
        end
      endcase
    end
  end

  wire _unused = &{ena, uio_in[7:2], 1'b0};
endmodule
