`timescale 1ns/1ps
// 空間メモリー トップ。
//
//   addr   : NUM_ARRAYS 本のアドレスを連結したもの（アレイ a = addr[a*BIT_WIDTH +: BIT_WIDTH]）
//   read / write : 1 クロックのパルス。resp_valid が立ったクロックで hit / hit_index /
//            multi_hit / full_reject が有効。rdata と data_valid はその次のクロック
//   mask_shift / mask_reset : 近傍検索のマスク操作（6 章）。ホストが直接回す場合
//   mask_ovr_en / mask_ovr  : search_sequencer が段から作ったマスクを差し込む場合
//   busy   : CAM が登録中（BRAM 版のみ）。busy 中の read / write は受け付けない
//
// CAM_IMPL = 0 : cam_array（CAM セル版、ASIC の本設計）。検索は組み合わせ、resp_valid は同じクロック
// CAM_IMPL = 1 : cam_array_bram（FPGA 向け）。検索は 1 クロック遅れ、resp_valid も 1 クロック後
//
// Write の判定は常に完全一致。マスクレジスタは触らず、組み合わせ回路で全 1 に差し替える（4 章 共通規則）。
module top_spatial_memory #(
  parameter BIT_WIDTH   = 32,
  parameter ENTRY_BITS  = 8,
  parameter NUM_ARRAYS  = 1,
  parameter DATA_WIDTH  = 64,
  parameter SHIFT_STEP  = 1,
  parameter NEWEST_WINS = 0,
  parameter CAM_IMPL    = 0,
  parameter SLICE_BITS  = 8
)(
  input  wire                            clk,
  input  wire                            rst_n,
  input  wire                            read,
  input  wire                            write,
  input  wire [NUM_ARRAYS*BIT_WIDTH-1:0] addr,
  input  wire [DATA_WIDTH-1:0]           wdata,
  input  wire                            mask_shift,
  input  wire                            mask_reset,
  input  wire                            mask_ovr_en,  // 1 のとき mask_ovr を使う（search_sequencer 用）
  input  wire [BIT_WIDTH-1:0]            mask_ovr,
  output wire [DATA_WIDTH-1:0]           rdata,
  output reg                             data_valid,   // rdata が有効（Read + HIT の resp_valid の翌クロック）
  output wire                            resp_valid,   // hit 系の出力が有効
  output wire                            hit,
  output wire                            not_find,
  output wire                            multi_hit,
  output wire [ENTRY_BITS-1:0]           hit_index,
  output wire                            full,
  output wire                            full_reject,
  output wire                            busy,
  output wire [ENTRY_BITS:0]             count,
  output wire [BIT_WIDTH-1:0]            mask,
  output wire                            mask_empty
);
  localparam NUM_ENTRIES = 1 << ENTRY_BITS;
  localparam LATENCY     = (CAM_IMPL == 0) ? 0 : 1;

  // ---- マスク -------------------------------------------------------------
  mask_register #(.BIT_WIDTH(BIT_WIDTH), .SHIFT_STEP(SHIFT_STEP)) u_mask (
    .clk(clk), .rst_n(rst_n),
    .shift_en(mask_shift), .reset_mask(mask_reset),
    .mask(mask), .mask_empty(mask_empty)
  );

  // Write は常に完全一致。それ以外は、シーケンサーが握っていればその値、でなければマスクレジスタ
  wire [BIT_WIDTH-1:0] mask_eff = write ? {BIT_WIDTH{1'b1}} : (mask_ovr_en ? mask_ovr : mask);

  // ---- 要求のパイプライン（CAM の遅延に合わせる） ---------------------------------
  wire                            read_d, write_d;
  wire [NUM_ARRAYS*BIT_WIDTH-1:0] addr_d;
  wire [DATA_WIDTH-1:0]           wdata_d;

  generate
    if (LATENCY == 0) begin : NOPIPE
      assign read_d  = read;
      assign write_d = write;
      assign addr_d  = addr;
      assign wdata_d = wdata;
    end else begin : PIPE
      reg                            read_q, write_q;
      reg [NUM_ARRAYS*BIT_WIDTH-1:0] addr_q;
      reg [DATA_WIDTH-1:0]           wdata_q;
      always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
          read_q <= 1'b0; write_q <= 1'b0;
          addr_q <= {(NUM_ARRAYS*BIT_WIDTH){1'b0}}; wdata_q <= {DATA_WIDTH{1'b0}};
        end else begin
          read_q <= read; write_q <= write; addr_q <= addr; wdata_q <= wdata;
        end
      end
      assign read_d  = read_q;
      assign write_d = write_q;
      assign addr_d  = addr_q;
      assign wdata_d = wdata_q;
    end
  endgenerate

  assign resp_valid = read_d | write_d;

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
  wire [NUM_ARRAYS-1:0]              cam_busy;

  genvar a;
  generate
    for (a = 0; a < NUM_ARRAYS; a = a + 1) begin : ARR
      if (CAM_IMPL == 0) begin : FF
        cam_array #(.BIT_WIDTH(BIT_WIDTH), .ENTRY_BITS(ENTRY_BITS)) u_cam (
          .clk(clk), .rst_n(rst_n),
          .input_addr(addr[a*BIT_WIDTH +: BIT_WIDTH]), .mask(mask_eff),
          .match_vec(match_vec[a*NUM_ENTRIES +: NUM_ENTRIES]),
          .we(cam_we), .wr_ptr(wr_ptr), .wr_addr(addr_d[a*BIT_WIDTH +: BIT_WIDTH]),
          .busy(cam_busy[a])
        );
      end else begin : BRAM
        cam_array_bram #(.BIT_WIDTH(BIT_WIDTH), .ENTRY_BITS(ENTRY_BITS), .SLICE_BITS(SLICE_BITS)) u_cam (
          .clk(clk), .rst_n(rst_n),
          .input_addr(addr[a*BIT_WIDTH +: BIT_WIDTH]), .mask(mask_eff),
          .match_vec(match_vec[a*NUM_ENTRIES +: NUM_ENTRIES]),
          .we(cam_we), .wr_ptr(wr_ptr), .wr_addr(addr_d[a*BIT_WIDTH +: BIT_WIDTH]),
          .busy(cam_busy[a])
        );
      end
    end
  endgenerate

  assign busy = |cam_busy;

  // ---- 行ごとの全次元 AND → hit_index ---------------------------------------
  wire [NUM_ENTRIES-1:0] row_hit;
  and_reduction_tree #(.NUM_ARRAYS(NUM_ARRAYS), .NUM_ENTRIES(NUM_ENTRIES)) u_and (
    .match_vec(match_vec), .row_hit(row_hit), .global_hit(hit), .not_find(not_find)
  );

  priority_encoder #(.NUM_ENTRIES(NUM_ENTRIES), .ENTRY_BITS(ENTRY_BITS), .NEWEST_WINS(NEWEST_WINS)) u_enc (
    .row_hit(row_hit), .hit_index(hit_index), .multi_hit(multi_hit)
  );

  // ---- 読み書き制御 ---------------------------------------------------------
  // busy 中の write は無視する（BRAM 版が登録中に次の登録を受けられないため）
  wire                  write_eff = write_d & ~busy;
  wire                  sram_we;
  wire [ENTRY_BITS-1:0] sram_waddr;
  output_ctrl #(.ENTRY_BITS(ENTRY_BITS)) u_ctrl (
    .read(read_d), .write(write_eff), .hit(hit), .full(full),
    .hit_index(hit_index), .wr_ptr(wr_ptr),
    .cam_we(cam_we), .wr_inc(wr_inc),
    .sram_we(sram_we), .sram_waddr(sram_waddr), .full_reject(full_reject)
  );

  // ---- データメモリー -------------------------------------------------------
  data_sram #(.DATA_WIDTH(DATA_WIDTH), .ENTRY_BITS(ENTRY_BITS)) u_sram (
    .clk(clk), .we(sram_we), .waddr(sram_waddr), .wdata(wdata_d),
    .raddr(hit_index), .rdata(rdata)
  );

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) data_valid <= 1'b0;
    else        data_valid <= read_d & hit;
  end

endmodule
