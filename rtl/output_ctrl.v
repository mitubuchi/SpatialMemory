`timescale 1ns/1ps
// 読み書きの制御。CAM の HIT / NotFind と操作種別から、どこに何を書くかを決める。
//
//   Read  + HIT      : RAM[hit_index] を読む
//   Write + HIT      : RAM[hit_index] を上書き（CAM と WR_PTR は変えない。FULL でも可）
//   Write + NotFind  : CAM[WR_PTR] と RAM[WR_PTR] に新規登録し WR_PTR++（FULL なら拒否）
//   Read  + NotFind  : 何もしない
//
// 仕様書 4 章。
module output_ctrl #(
  parameter ENTRY_BITS = 8
)(
  input  wire                  read,
  input  wire                  write,
  input  wire                  hit,          // 完全一致での HIT（Write 時のマスクは全 1）
  input  wire                  full,
  input  wire [ENTRY_BITS-1:0] hit_index,
  input  wire [ENTRY_BITS-1:0] wr_ptr,
  output wire                  cam_we,       // CAM へ新規登録
  output wire                  wr_inc,       // WR_PTR を進める
  output wire                  sram_we,
  output wire [ENTRY_BITS-1:0] sram_waddr,
  output wire                  full_reject   // FULL で新規登録を拒否した
);
  wire new_entry = write & ~hit & ~full;
  wire overwrite = write &  hit;

  assign cam_we      = new_entry;
  assign wr_inc      = new_entry;
  assign sram_we     = new_entry | overwrite;
  assign sram_waddr  = hit ? hit_index : wr_ptr;
  assign full_reject = write & ~hit & full;

endmodule
