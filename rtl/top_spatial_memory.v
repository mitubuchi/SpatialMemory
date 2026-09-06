`timescale 1ns/1ps
// 空間メモリー トップ。
//
//   addr   : NUM_ARRAYS 本のアドレスを連結したもの（アレイ a = addr[a*BIT_WIDTH +: BIT_WIDTH]）
//   read   : 1 クロックのパルス。同じクロックで hit / hit_index が組み合わせで出て、
//            次のクロックで rdata と data_valid が出る
//   write  : 1 クロックのパルス。そのクロックの立ち上がりで CAM / SRAM / WR_PTR が更新される
//   mask_shift / mask_reset : 近傍検索のマスク操作（6 章）
//
// Write の判定は常に完全一致。マスクレジスタは触らず、組み合わせ回路で全 1 に差し替える（4 章 共通規則）。
module top_spatial_memory #(
  parameter BIT_WIDTH   = 32,
  parameter ENTRY_BITS  = 8,
  parameter NUM_ARRAYS  = 1,
  parameter DATA_WIDTH  = 64,
  parameter SHIFT_STEP  = 1,
  parameter NEWEST_WINS = 0
)(
  input  wire                            clk,
  input  wire                            rst_n,
  input  wire                            read,
  input  wire                            write,
  input  wire [NUM_ARRAYS*BIT_WIDTH-1:0] addr,
  input  wire [DATA_WIDTH-1:0]           wdata,
  input  wire                            mask_shift,
  input  wire                            mask_reset,
  output wire [DATA_WIDTH-1:0]           rdata,
  output reg                             data_valid,   // rdata が有効（Read + HIT の翌クロック）
  output wire                            hit,          // 組み合わせ。read / write と同じクロックで有効
  output wire                            not_find,
  output wire                            multi_hit,
  output wire [ENTRY_BITS-1:0]           hit_index,
  output wire                            full,
  output wire                            full_reject,
  output wire [ENTRY_BITS:0]             count,
  output wire [BIT_WIDTH-1:0]            mask,
  output wire                            mask_empty
);
  localparam NUM_ENTRIES = 1 << ENTRY_BITS;

  // ---- マスク -------------------------------------------------------------
  mask_register #(.BIT_WIDTH(BIT_WIDTH), .SHIFT_STEP(SHIFT_STEP)) u_mask (
    .clk(clk), .rst_n(rst_n),
    .shift_en(mask_shift), .reset_mask(mask_reset),
    .mask(mask), .mask_empty(mask_empty)
  );

  // Write は常に完全一致
  wire [BIT_WIDTH-1:0] mask_eff = write ? {BIT_WIDTH{1'b1}} : mask;

  // ---- 書き込みポインター ---------------------------------------------------
  wire                  wr_inc;
  wire [ENTRY_BITS-1:0] wr_ptr;
  wr_pointer #(.ENTRY_BITS(ENTRY_BITS)) u_wrptr (
    .clk(clk), .rst_n(rst_n), .inc(wr_inc),
    .wr_ptr(wr_ptr), .count(count), .full(full)
  );

  // ---- CAM アレイ（次元ごと） ----------------------------------------------
  wire                               cam_we;
  wire [NUM_ARRAYS*NUM_ENTRIES-1:0]  match_vec;

  genvar a;
  generate
    for (a = 0; a < NUM_ARRAYS; a = a + 1) begin : ARR
      cam_array #(.BIT_WIDTH(BIT_WIDTH), .ENTRY_BITS(ENTRY_BITS)) u_cam (
        .clk(clk), .rst_n(rst_n),
        .we(cam_we), .wr_ptr(wr_ptr),
        .input_addr(addr[a*BIT_WIDTH +: BIT_WIDTH]),
        .mask(mask_eff),
        .match_vec(match_vec[a*NUM_ENTRIES +: NUM_ENTRIES])
      );
    end
  endgenerate

  // ---- 行ごとの全次元 AND → hit_index ---------------------------------------
  wire [NUM_ENTRIES-1:0] row_hit;
  and_reduction_tree #(.NUM_ARRAYS(NUM_ARRAYS), .NUM_ENTRIES(NUM_ENTRIES)) u_and (
    .match_vec(match_vec), .row_hit(row_hit), .global_hit(hit), .not_find(not_find)
  );

  priority_encoder #(.NUM_ENTRIES(NUM_ENTRIES), .ENTRY_BITS(ENTRY_BITS), .NEWEST_WINS(NEWEST_WINS)) u_enc (
    .row_hit(row_hit), .hit_index(hit_index), .multi_hit(multi_hit)
  );

  // ---- 読み書き制御 ---------------------------------------------------------
  wire                  sram_we;
  wire [ENTRY_BITS-1:0] sram_waddr;
  output_ctrl #(.ENTRY_BITS(ENTRY_BITS)) u_ctrl (
    .read(read), .write(write), .hit(hit), .full(full),
    .hit_index(hit_index), .wr_ptr(wr_ptr),
    .cam_we(cam_we), .wr_inc(wr_inc),
    .sram_we(sram_we), .sram_waddr(sram_waddr), .full_reject(full_reject)
  );

  // ---- データメモリー -------------------------------------------------------
  data_sram #(.DATA_WIDTH(DATA_WIDTH), .ENTRY_BITS(ENTRY_BITS)) u_sram (
    .clk(clk), .we(sram_we), .waddr(sram_waddr), .wdata(wdata),
    .raddr(hit_index), .rdata(rdata)
  );

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) data_valid <= 1'b0;
    else        data_valid <= read & hit;
  end

endmodule
