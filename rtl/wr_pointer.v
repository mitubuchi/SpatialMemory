`timescale 1ns/1ps
// 書き込みポインター。行アドレスより 1 bit 広いカウンターで、最上位ビットが full。
// ENTRY_BITS 幅のままだと最後の行を書いた瞬間に 0 へ戻り、空と満杯を区別できない。
// full の間は inc を無視し、wrap して entry 0 を壊さない。
// 仕様書 3 章 / 9 章。
module wr_pointer #(
  parameter ENTRY_BITS = 8   // エントリ数 = 2^ENTRY_BITS
)(
  input  wire                  clk,
  input  wire                  rst_n,
  input  wire                  inc,      // 新規登録（Write + NotFind）で 1
  output wire [ENTRY_BITS-1:0] wr_ptr,   // 次に書く行
  output wire [ENTRY_BITS:0]   count,    // 登録済みエントリ数（0 .. 2^ENTRY_BITS）
  output wire                  full      // 全行使用済み
);
  reg [ENTRY_BITS:0] cnt;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n)            cnt <= {(ENTRY_BITS+1){1'b0}};
    else if (inc && !full) cnt <= cnt + 1'b1;
  end

  assign count  = cnt;
  assign wr_ptr = cnt[ENTRY_BITS-1:0];
  assign full   = cnt[ENTRY_BITS];

endmodule
