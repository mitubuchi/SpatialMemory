`timescale 1ns/1ps
// LSB シフトマスクレジスタ。shift_en で LSB 側から SHIFT_STEP ビットずつ 0 にする。
// Morton コードで D 次元を詰めているときは SHIFT_STEP = D にすると、
// 1 ステップで全軸が同時に 1 段粗いセルへ広がる。
// 仕様書 6 章 / 9 章。
module mask_register #(
  parameter BIT_WIDTH  = 32,
  parameter SHIFT_STEP = 1
)(
  input  wire                  clk,
  input  wire                  rst_n,
  input  wire                  shift_en,    // LSB シフト実行
  input  wire                  reset_mask,  // マスクをリセット（全 1）
  output reg  [BIT_WIDTH-1:0]  mask,
  output wire                  mask_empty   // マスクが全 0（検索終了）
);
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n)          mask <= {BIT_WIDTH{1'b1}};
    else if (reset_mask) mask <= {BIT_WIDTH{1'b1}};
    else if (shift_en)   mask <= mask << SHIFT_STEP;
  end

  assign mask_empty = (mask == {BIT_WIDTH{1'b0}});

endmodule
