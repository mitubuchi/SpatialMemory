`timescale 1ns/1ps
// row_hit から hit_index を作る。複数行が立っているときは最小インデックス
//（最も古いエントリ）を採り、multi_hit を立てる。
// NEWEST_WINS = 1 で最大インデックス（最も新しいエントリ）に切り替える。
//
// 2 分木で畳む（log2(NUM_ENTRIES) 段）。for ループの直列記述だと合成後の
// 論理段数が NUM_ENTRIES に比例して伸び、256 エントリで検索が 1 クロックに
// 収まらなくなる。
//
// 木の各ノードは (any, idx, multi) を持つ。
//   any   : 部分木に 1 が有るか
//   idx   : 部分木の中で採る行のインデックス（ノードから見た相対値）
//   multi : 部分木に 1 が 2 つ以上有るか
// レベル l のノード n は、レベル l-1 のノード 2n（左 = 小さいインデックス）と
// 2n+1（右）を併合する。
// 仕様書 6 章「多重ヒットの規則」/ 9 章。
module priority_encoder #(
  parameter NUM_ENTRIES = 256,
  parameter ENTRY_BITS  = 8,
  parameter NEWEST_WINS = 0
)(
  input  wire [NUM_ENTRIES-1:0] row_hit,
  output wire [ENTRY_BITS-1:0]  hit_index,
  output wire                   multi_hit    // 2 行以上一致
);
  // 全レベルのノードを 1 本の配列に並べる。レベル l の先頭 = 2*N - 2*(N>>l)
  //   l=0: 0（N 個）, l=1: N（N/2 個）, l=2: 1.5N（N/4 個）, ... , l=ENTRY_BITS: 2N-2（1 個）
  localparam TOT = 2 * NUM_ENTRIES;

  wire [TOT-1:0]            any_all;
  wire [TOT-1:0]            multi_all;
  wire [TOT*ENTRY_BITS-1:0] idx_all;   // ノードごとに ENTRY_BITS 幅。未使用の上位ビットは 0

  genvar l, n;
  generate
    for (l = 0; l <= ENTRY_BITS; l = l + 1) begin : LVL
      localparam integer CNT = NUM_ENTRIES >> l;            // このレベルのノード数
      localparam integer OFS = 2 * NUM_ENTRIES - 2 * CNT;   // このレベルの先頭
      localparam integer POF = 2 * NUM_ENTRIES - 4 * CNT;   // 1 つ下のレベルの先頭（l >= 1）
      for (n = 0; n < CNT; n = n + 1) begin : NODE
        if (l == 0) begin : LEAF
          assign any_all[OFS + n]                          = row_hit[n];
          assign multi_all[OFS + n]                        = 1'b0;
          assign idx_all[(OFS + n)*ENTRY_BITS +: ENTRY_BITS] = {ENTRY_BITS{1'b0}};
        end else begin : MERGE
          wire                  any_l   = any_all[POF + 2*n];
          wire                  any_r   = any_all[POF + 2*n + 1];
          wire                  multi_l = multi_all[POF + 2*n];
          wire                  multi_r = multi_all[POF + 2*n + 1];
          wire [ENTRY_BITS-1:0] idx_l   = idx_all[(POF + 2*n)*ENTRY_BITS +: ENTRY_BITS];
          wire [ENTRY_BITS-1:0] idx_r   = idx_all[(POF + 2*n + 1)*ENTRY_BITS +: ENTRY_BITS];

          // 右（大きいインデックス）を採るか。最小優先なら左に 1 が無いときだけ、
          // 最新優先なら右に 1 が有れば右。
          wire take_r = NEWEST_WINS ? any_r : ~any_l;

          // 右を採るときは、このレベルで決まるビット（l-1）を 1 にする
          wire [ENTRY_BITS-1:0] idx_r_tagged = idx_r | ({{(ENTRY_BITS-1){1'b0}}, 1'b1} << (l - 1));

          assign any_all[OFS + n]                          = any_l | any_r;
          assign multi_all[OFS + n]                        = multi_l | multi_r | (any_l & any_r);
          assign idx_all[(OFS + n)*ENTRY_BITS +: ENTRY_BITS] = take_r ? idx_r_tagged : idx_l;
        end
      end
    end
  endgenerate

  // 根 = 最後のレベルの唯一のノード（先頭 2N-2）
  assign hit_index = idx_all[(TOT - 2)*ENTRY_BITS +: ENTRY_BITS];
  assign multi_hit = multi_all[TOT - 2];

endmodule
