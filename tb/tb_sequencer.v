// 近傍検索シーケンサー（境界対処 A）のテスト。
//   A: スカラー 8 bit。0111 と 1000 が段 0 の隣接セルで出会うこと、中心だけなら段 4 まで要ること、
//      k_max で打ち切れること、空間の端（0xFF の +1）を飛ばすこと
//   B: 2 次元 Morton（各軸 4 bit）。(4,4) から (3,3) が全隣接なら段 0 の角、面隣接なら段 1 の +y に
//      Q(5,6) が先に見つかること、中心だけなら段 2 で Q、(1,5) からは段 3 で多重ヒット、(0,0) からの角
// 仕様書 6 章「境界問題と対処」。
`timescale 1ns/1ps
module tb_sequencer;
  parameter CAM_IMPL = 0;   // 0: CAM セル版 / 1: BRAM 版（iverilog -P tb_sequencer.CAM_IMPL=1）
  localparam BW = 8, EB = 3, DW = 8;

  reg clk = 0, rst_n = 0;
  always #5 clk = ~clk;

  integer pass = 0, fail = 0;
  task check(input cond, input [8*80-1:0] msg);
    begin
      if (cond) pass = pass + 1;
      else begin fail = fail + 1; $display("FAIL: %0s", msg); end
    end
  endtask

  // ---------------------------------------------------------------- セット A: スカラー
  reg           a_write = 0, a_start = 0;
  reg  [BW-1:0] a_waddr = 0, a_saddr = 0;
  reg  [DW-1:0] a_wdata = 0;
  reg  [7:0]    a_kmax = 0;
  reg  [1:0]    a_mode = 0;
  wire          a_qread, a_active, a_done, a_found, a_multi, a_resp, a_hit, a_busy, a_dv, a_rmulti;
  wire [BW-1:0] a_qaddr, a_qmask, a_mask;
  wire [7:0]    a_level;
  wire [5:0]    a_cell;
  wire [EB-1:0] a_hidx, a_rhidx;
  wire [DW-1:0] a_rdata;
  wire          a_nf, a_full, a_frej, a_me;
  wire [EB:0]   a_count;

  top_spatial_memory #(.BIT_WIDTH(BW), .ENTRY_BITS(EB), .NUM_ARRAYS(1), .DATA_WIDTH(DW), .CAM_IMPL(CAM_IMPL)) mem_a (
    .clk(clk), .rst_n(rst_n), .read(a_qread), .write(a_write),
    .addr(a_active ? a_qaddr : a_waddr), .wdata(a_wdata),
    .mask_shift(1'b0), .mask_reset(1'b0), .mask_ovr_en(a_active), .mask_ovr(a_qmask),
    .rdata(a_rdata), .data_valid(a_dv), .resp_valid(a_resp), .hit(a_hit), .not_find(a_nf),
    .multi_hit(a_rmulti), .hit_index(a_rhidx), .full(a_full), .full_reject(a_frej),
    .busy(a_busy), .count(a_count), .mask(a_mask), .mask_empty(a_me)
  );
  search_sequencer #(.BIT_WIDTH(BW), .ENTRY_BITS(EB), .DIMS(1)) seq_a (
    .clk(clk), .rst_n(rst_n),
    .start(a_start), .addr(a_saddr), .k_max(a_kmax), .mode(a_mode),
    .done(a_done), .found(a_found), .level(a_level), .cell_no(a_cell), .hit_index(a_hidx), .multi_hit(a_multi), .active(a_active),
    .q_read(a_qread), .q_addr(a_qaddr), .q_mask(a_qmask),
    .resp_valid(a_resp), .hit(a_hit), .r_hit_index(a_rhidx), .r_multi_hit(a_rmulti), .busy(a_busy)
  );

  task a_wr(input [BW-1:0] ad, input [DW-1:0] d);
    begin
      #1; while (a_busy) begin @(negedge clk); #1; end
      @(negedge clk); a_waddr = ad; a_wdata = d; a_write = 1;
      #1; if (!a_resp) begin @(negedge clk); a_write = 0; #1; while (!a_resp) begin @(negedge clk); #1; end end
      @(negedge clk); a_write = 0;
      #1; while (a_busy) begin @(negedge clk); #1; end
    end
  endtask

  task a_search(input [BW-1:0] ad, input [7:0] km, input [1:0] md);
    begin
      #1; while (a_busy) begin @(negedge clk); #1; end
      @(negedge clk); a_saddr = ad; a_kmax = km; a_mode = md; a_start = 1;
      @(negedge clk); a_start = 0;
      #1; while (!a_done) begin @(negedge clk); #1; end
    end
  endtask

  // ---------------------------------------------------------------- セット B: 2 次元 Morton
  reg           b_write = 0, b_start = 0;
  reg  [BW-1:0] b_waddr = 0, b_saddr = 0;
  reg  [DW-1:0] b_wdata = 0;
  reg  [7:0]    b_kmax = 0;
  reg  [1:0]    b_mode = 0;
  wire          b_qread, b_active, b_done, b_found, b_multi, b_resp, b_hit, b_busy, b_dv, b_rmulti;
  wire [BW-1:0] b_qaddr, b_qmask, b_mask;
  wire [7:0]    b_level;
  wire [5:0]    b_cell;
  wire [EB-1:0] b_hidx, b_rhidx;
  wire [DW-1:0] b_rdata;
  wire          b_nf, b_full, b_frej, b_me;
  wire [EB:0]   b_count;

  top_spatial_memory #(.BIT_WIDTH(BW), .ENTRY_BITS(EB), .NUM_ARRAYS(1), .DATA_WIDTH(DW), .SHIFT_STEP(2), .CAM_IMPL(CAM_IMPL)) mem_b (
    .clk(clk), .rst_n(rst_n), .read(b_qread), .write(b_write),
    .addr(b_active ? b_qaddr : b_waddr), .wdata(b_wdata),
    .mask_shift(1'b0), .mask_reset(1'b0), .mask_ovr_en(b_active), .mask_ovr(b_qmask),
    .rdata(b_rdata), .data_valid(b_dv), .resp_valid(b_resp), .hit(b_hit), .not_find(b_nf),
    .multi_hit(b_rmulti), .hit_index(b_rhidx), .full(b_full), .full_reject(b_frej),
    .busy(b_busy), .count(b_count), .mask(b_mask), .mask_empty(b_me)
  );
  search_sequencer #(.BIT_WIDTH(BW), .ENTRY_BITS(EB), .DIMS(2)) seq_b (
    .clk(clk), .rst_n(rst_n),
    .start(b_start), .addr(b_saddr), .k_max(b_kmax), .mode(b_mode),
    .done(b_done), .found(b_found), .level(b_level), .cell_no(b_cell), .hit_index(b_hidx), .multi_hit(b_multi), .active(b_active),
    .q_read(b_qread), .q_addr(b_qaddr), .q_mask(b_qmask),
    .resp_valid(b_resp), .hit(b_hit), .r_hit_index(b_rhidx), .r_multi_hit(b_rmulti), .busy(b_busy)
  );

  task b_wr(input [BW-1:0] ad, input [DW-1:0] d);
    begin
      #1; while (b_busy) begin @(negedge clk); #1; end
      @(negedge clk); b_waddr = ad; b_wdata = d; b_write = 1;
      #1; if (!b_resp) begin @(negedge clk); b_write = 0; #1; while (!b_resp) begin @(negedge clk); #1; end end
      @(negedge clk); b_write = 0;
      #1; while (b_busy) begin @(negedge clk); #1; end
    end
  endtask

  task b_search(input [BW-1:0] ad, input [7:0] km, input [1:0] md);
    begin
      #1; while (b_busy) begin @(negedge clk); #1; end
      @(negedge clk); b_saddr = ad; b_kmax = km; b_mode = md; b_start = 1;
      @(negedge clk); b_start = 0;
      #1; while (!b_done) begin @(negedge clk); #1; end
    end
  endtask

  // addr = y3 x3 y2 x2 y1 x1 y0 x0（仕様書 6 章）
  function [7:0] morton2(input [3:0] x, input [3:0] y);
    integer i;
    begin
      for (i = 0; i < 4; i = i + 1) begin
        morton2[2*i]   = x[i];
        morton2[2*i+1] = y[i];
      end
    end
  endfunction

  // セル番号: 軸 0 の桁 + 3 × 軸 1 の桁（0 = 中心、1 = +1、2 = -1）
  localparam C_CENTER = 6'd0;
  localparam C_XM     = 6'd2;             // -x
  localparam C_YP     = 6'd3;             // +y
  localparam C_XP_YP  = 6'd1 + 6'd3;      // +x, +y
  localparam C_XM_YM  = 6'd2 + 6'd6;      // -x, -y

  localparam MODE_CENTER = 2'd0, MODE_FACE = 2'd1, MODE_ALL = 2'd2;

  initial begin
    repeat (2) @(negedge clk); rst_n = 1;

    // ---------------- A: スカラー ----------------
    a_search(8'h08, 8'd7, MODE_ALL);
    check(!a_found, "A0 empty memory: not found");

    a_wr(8'h07, 8'h07);   // 0111 → 行 0
    a_wr(8'h80, 8'h80);   // 1000 0000 → 行 1

    a_search(8'h08, 8'd7, MODE_ALL);
    check(a_found && a_level == 0 && a_cell == C_XM && a_hidx == 0 && a_rdata == 8'h07,
          "A1 1000 finds 0111 at level 0 in the -x cell");

    a_search(8'h08, 8'd7, MODE_CENTER);
    check(a_found && a_level == 4 && a_cell == C_CENTER && a_hidx == 0,
          "A2 center-only needs level 4 (mask F0) to reach 0111");

    a_search(8'h08, 8'd2, MODE_CENTER);
    check(!a_found, "A3 k_max=2 cuts the search off");

    a_search(8'hFF, 8'd0, MODE_ALL);
    check(!a_found, "A4 +1 from 0xFF overflows and is skipped; -1 (0xFE) misses");

    a_search(8'h81, 8'd0, MODE_FACE);
    check(a_found && a_level == 0 && a_cell == C_XM && a_hidx == 1 && a_rdata == 8'h80,
          "A5 face mode finds 0x80 from 0x81 at level 0");

    // ---------------- B: 2 次元 Morton ----------------
    b_wr(morton2(4'd3, 4'd3), 8'hA3);   // P = (3,3) → 行 0
    b_wr(morton2(4'd5, 4'd6), 8'hB5);   // Q = (5,6) → 行 1

    b_search(morton2(4'd4, 4'd4), 8'd3, MODE_ALL);
    check(b_found && b_level == 0 && b_cell == C_XM_YM && b_hidx == 0 && b_rdata == 8'hA3,
          "B1 (4,4) all-neighbor: P(3,3) in the (-x,-y) corner at level 0");

    b_search(morton2(4'd4, 4'd4), 8'd3, MODE_FACE);
    check(b_found && b_level == 1 && b_cell == C_YP && b_hidx == 1 && b_rdata == 8'hB5,
          "B2 (4,4) face-neighbor: corner is invisible, Q(5,6) found in +y cell at level 1");

    b_search(morton2(4'd4, 4'd4), 8'd3, MODE_CENTER);
    check(b_found && b_level == 2 && b_cell == C_CENTER && !b_multi && b_hidx == 1,
          "B3 (4,4) center-only: level 2 (4x4 cell [4..7]^2) reaches Q, P still outside");

    // (1,5) の 4x4 セル [0..3]x[4..7] には P も Q も無い。8x8 で両方に当たる
    b_search(morton2(4'd1, 4'd5), 8'd3, MODE_CENTER);
    check(b_found && b_level == 3 && b_cell == C_CENTER && b_multi && b_hidx == 0,
          "B3b (1,5) center-only: level 3 (8x8) hits both, lowest index P");

    b_search(morton2(4'd0, 4'd0), 8'd3, MODE_ALL);
    check(b_found && b_level == 1 && b_cell == C_XP_YP && b_hidx == 0,
          "B4 (0,0): -x/-y underflow skipped, P in (+x,+y) corner at level 1");

    b_search(morton2(4'd4, 4'd4), 8'd1, MODE_CENTER);
    check(!b_found, "B5 (4,4) center-only with k_max=1: not found");

    b_search(morton2(4'd5, 4'd6), 8'd0, MODE_CENTER);
    check(b_found && b_level == 0 && b_hidx == 1, "B6 exact hit at level 0");

    $display("tb_sequencer: %0d passed, %0d failed", pass, fail);
    if (fail == 0) $display("ALL TESTS PASSED");
    $finish;
  end
endmodule
