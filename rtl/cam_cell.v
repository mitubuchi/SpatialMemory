`timescale 1ns/1ps
// 1 ビット分の CAM セル。記憶ビットと入力ビットの XNOR に、マスクを OR で適用する。
// mask_bit = 0 のビットは比較をスキップ（必ず一致扱い）。
// 仕様書 3 章 / 9 章。
module cam_cell (
  input  wire clk,
  input  wire rst_n,
  input  wire we,           // 書き込みイネーブル（行選択済み）
  input  wire wr_bit,       // 記憶するビット
  input  wire input_bit,    // 検索アドレスビット
  input  wire mask_bit,     // マスクビット（0 = スキップ）
  output wire match         // 一致フラグ
);
  reg stored_bit;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n)    stored_bit <= 1'b0;
    else if (we)   stored_bit <= wr_bit;
  end

  // XNOR: 一致で 1、不一致で 0
  wire xnor_out = ~(stored_bit ^ input_bit);

  // マスクが 0 なら強制的に一致（AND にすると無視したいビットが不一致になる）
  assign match = xnor_out | ~mask_bit;

endmodule
