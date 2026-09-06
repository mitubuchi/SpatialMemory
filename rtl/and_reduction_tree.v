`timescale 1ns/1ps
// 並列 CAM アレイの AND を「行ごと」に取る。
// アレイ単位の HIT フラグ同士を AND すると、#1 が 3 行目、#2 が 7 行目で
// 一致しただけで HIT になり、同一エントリで一致したことを保証できない。
// 仕様書 5 章 / 9 章。
module and_reduction_tree #(
  parameter NUM_ARRAYS  = 4,    // 並列 CAM アレイ数（次元数）
  parameter NUM_ENTRIES = 256   // エントリ数（行数）
)(
  // 各アレイの行マッチベクトルを連結したもの（アレイ a の行 i = match_vec[a*NUM_ENTRIES + i]）
  input  wire [NUM_ARRAYS*NUM_ENTRIES-1:0] match_vec,
  output wire [NUM_ENTRIES-1:0]            row_hit,     // 全次元で一致した行
  output wire                              global_hit,  // 1 行でも残れば HIT
  output wire                              not_find     // 未発見フラグ
);
  genvar i, a;
  generate
    for (i = 0; i < NUM_ENTRIES; i = i + 1) begin : ROW
      wire [NUM_ARRAYS-1:0] dim_match;
      for (a = 0; a < NUM_ARRAYS; a = a + 1) begin : ARR
        assign dim_match[a] = match_vec[a*NUM_ENTRIES + i];
      end
      // 同じ行が全次元で一致したときだけ 1
      assign row_hit[i] = &dim_match;
    end
  endgenerate

  assign global_hit = |row_hit;
  assign not_find   = ~global_hit;

endmodule
