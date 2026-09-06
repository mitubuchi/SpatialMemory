`timescale 1ns/1ps
// N 行 × M ビットの CAM アレイ。we と wr_ptr を全行へブロードキャストし、
// 各行が ROW_INDEX との比較で自分宛てかを判定する。
// 出力は行ごとのマッチベクトル（アレイ単位の HIT フラグではない）。
// 仕様書 9 章。
module cam_array #(
  parameter BIT_WIDTH  = 32,
  parameter ENTRY_BITS = 8
)(
  input  wire                        clk,
  input  wire                        rst_n,
  input  wire                        we,
  input  wire [ENTRY_BITS-1:0]       wr_ptr,
  input  wire [BIT_WIDTH-1:0]        input_addr,
  input  wire [BIT_WIDTH-1:0]        mask,
  output wire [(1<<ENTRY_BITS)-1:0]  match_vec
);
  localparam NUM_ENTRIES = 1 << ENTRY_BITS;

  genvar r;
  generate
    for (r = 0; r < NUM_ENTRIES; r = r + 1) begin : ROW
      cam_row #(
        .BIT_WIDTH  (BIT_WIDTH),
        .ENTRY_BITS (ENTRY_BITS),
        .ROW_INDEX  (r)
      ) u_row (
        .clk        (clk),
        .rst_n      (rst_n),
        .we         (we),
        .wr_ptr     (wr_ptr),
        .input_addr (input_addr),
        .mask       (mask),
        .row_match  (match_vec[r])
      );
    end
  endgenerate

endmodule
