`timescale 1ns/1ps
// 1 行分の CAM セル群。WR_PTR が自分の行を指しているときだけ書き込む。
//
// valid ビットを持つ。リセット直後は全セルが 0 なので、これが無いと
// アドレス 0 の検索が未使用の全行に HIT してしまう。
// 仕様書 9 章。
module cam_row #(
  parameter BIT_WIDTH  = 32,
  parameter ENTRY_BITS = 8,
  parameter ROW_INDEX  = 0    // この行のインデックス（cam_array が generate で与える）
)(
  input  wire                  clk,
  input  wire                  rst_n,
  input  wire                  we,          // アレイ共通の書き込みイネーブル
  input  wire [ENTRY_BITS-1:0] wr_ptr,      // 書き込み先の行（WR_PTR）
  input  wire [BIT_WIDTH-1:0]  input_addr,
  input  wire [BIT_WIDTH-1:0]  mask,
  output wire                  row_match
);
  wire [BIT_WIDTH-1:0] cell_match;

  // 行選択：WR_PTR が自分の行を指しているときだけ書き込む。
  // これが無いと we で全行が同じアドレスに書き換わる。
  wire we_row = we & (wr_ptr == ROW_INDEX);

  reg valid;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n)      valid <= 1'b0;
    else if (we_row) valid <= 1'b1;
  end

  genvar i;
  generate
    for (i = 0; i < BIT_WIDTH; i = i + 1) begin : CELL
      cam_cell u_cell (
        .clk       (clk),
        .rst_n     (rst_n),
        .we        (we_row),
        .input_bit (input_addr[i]),
        .mask_bit  (mask[i]),
        .match     (cell_match[i])
      );
    end
  endgenerate

  // 全ビット AND → 行一致。未使用の行は一致させない。
  assign row_match = valid & (&cell_match);

endmodule
