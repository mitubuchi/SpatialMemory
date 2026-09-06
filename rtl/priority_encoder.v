`timescale 1ns/1ps
// row_hit から hit_index を作る。複数行が立っているときは最小インデックス
//（最も古いエントリ）を採り、multi_hit を立てる。
// NEWEST_WINS = 1 で最大インデックス（最も新しいエントリ）に切り替える。
// 仕様書 6 章「多重ヒットの規則」/ 9 章。
module priority_encoder #(
  parameter NUM_ENTRIES = 256,
  parameter ENTRY_BITS  = 8,
  parameter NEWEST_WINS = 0
)(
  input  wire [NUM_ENTRIES-1:0] row_hit,
  output reg  [ENTRY_BITS-1:0]  hit_index,
  output wire                   multi_hit    // 2 行以上一致
);
  integer i;
  always @* begin
    hit_index = {ENTRY_BITS{1'b0}};
    if (NEWEST_WINS) begin
      for (i = 0; i < NUM_ENTRIES; i = i + 1)        // 上から上書きして最大インデックスが残る
        if (row_hit[i]) hit_index = i[ENTRY_BITS-1:0];
    end else begin
      for (i = NUM_ENTRIES - 1; i >= 0; i = i - 1)   // 下から上書きして最小インデックスが残る
        if (row_hit[i]) hit_index = i[ENTRY_BITS-1:0];
    end
  end

  // 最下位の 1 を消して、まだ 1 が残っていれば多重ヒット
  assign multi_hit = |(row_hit & (row_hit - 1'b1));

endmodule
