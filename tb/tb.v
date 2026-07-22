// File-driven testbench for the attention scorer tile.
// Reads tb/vectors.txt (cmd byte + data byte per line, RESET lines are encoded by
// gen_tb_input.py as cmd=f), drives the DUT one line per clock, and writes uo_out
// after each edge to build/dut_out.txt for comparison against the golden model.
`timescale 1ns/1ps

module tb;
  reg clk = 0;
  reg rst_n = 0;
  reg [7:0] ui_in = 0;
  reg [7:0] uio_in = 0;
  wire [7:0] uo_out;
  wire [7:0] uio_out;
  wire [7:0] uio_oe;

  tt_um_hale_attn_scorer dut (
    .ui_in(ui_in), .uo_out(uo_out),
    .uio_in(uio_in), .uio_out(uio_out), .uio_oe(uio_oe),
    .ena(1'b1), .clk(clk), .rst_n(rst_n)
  );

  always #5 clk = ~clk;

  integer stim, outf, code;
  reg [7:0] cmd_b, data_b;

  initial begin
    stim = $fopen("tb/vectors_encoded.txt", "r");
    outf = $fopen("build/dut_out.txt", "w");
    if (stim == 0) begin $display("FATAL: no stimulus"); $finish; end

    // Reset for two cycles.
    rst_n = 0; @(posedge clk); @(posedge clk);
    rst_n = 1;

    while (!$feof(stim)) begin
      code = $fscanf(stim, "%h %h\n", cmd_b, data_b);
      if (code == 2) begin
        if (cmd_b == 8'h0f) begin
          // RESET line: pulse reset, log a fixed 00 like the golden model.
          rst_n = 0; @(posedge clk); @(posedge clk); rst_n = 1;
          $fwrite(outf, "00\n");
        end else begin
          ui_in = data_b;
          uio_in = {6'b0, cmd_b[1:0]};
          @(posedge clk);
          #1;
          $fwrite(outf, "%02x\n", uo_out);
        end
      end
    end
    $fclose(outf);
    $display("TB_DONE");
    $finish;
  end
endmodule
