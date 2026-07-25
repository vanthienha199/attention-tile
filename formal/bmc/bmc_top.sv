// Bounded miter: both implementations see identical free inputs; outputs must
// match on every cycle after reset is released. Reset is held for the first
// two cycles so the symbolic initial state of both sides is cleared the same
// way silicon would clear it.
module bmc_top(input clk, input [7:0] ui_in, input [1:0] cmd);
  reg [3:0] cnt = 0;
  always @(posedge clk) if (cnt < 15) cnt <= cnt + 1;
  wire rst_n = (cnt >= 2);

  wire [7:0] uio_in = {6'b0, cmd};
  wire [7:0] uo_a, uo_b, uio_out_a, uio_out_b, uio_oe_a, uio_oe_b;

  gold_scorer gold (.ui_in(ui_in), .uo_out(uo_a), .uio_in(uio_in),
    .uio_out(uio_out_a), .uio_oe(uio_oe_a), .ena(1'b1), .clk(clk), .rst_n(rst_n));
  gate_scorer gate (.ui_in(ui_in), .uo_out(uo_b), .uio_in(uio_in),
    .uio_out(uio_out_b), .uio_oe(uio_oe_b), .ena(1'b1), .clk(clk), .rst_n(rst_n));

  always @(posedge clk) if (cnt >= 3) begin
    assert (uo_a == uo_b);
    assert (uio_out_a == uio_out_b);
    assert (uio_oe_a == uio_oe_b);
  end
endmodule
