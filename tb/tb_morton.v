// Morton コード（2 次元、各軸 4 bit）での近傍検索。SHIFT_STEP = 2。
//   1 ステップで x, y が同時に 1 段粗くなり、1x1 → 2x2 → 4x4 のセルに広がる。
// 仕様書 6 章「座標データの登録：Morton コード」。
`timescale 1ns/1ps
module tb_morton;
  localparam BW = 8, EB = 2, DW = 8;

  reg           clk = 0, rst_n = 0;
  reg           read = 0, write = 0, mask_shift = 0, mask_reset = 0;
  reg  [BW-1:0] addr = 0;
  reg  [DW-1:0] wdata = 0;
  wire [DW-1:0] rdata;
  wire          data_valid, hit, not_find, multi_hit, full, full_reject, mask_empty;
  wire [EB-1:0] hit_index;
  wire [EB:0]   count;
  wire [BW-1:0] mask;

  top_spatial_memory #(.BIT_WIDTH(BW), .ENTRY_BITS(EB), .NUM_ARRAYS(1), .DATA_WIDTH(DW), .SHIFT_STEP(2)) dut (
    .clk(clk), .rst_n(rst_n), .read(read), .write(write), .addr(addr), .wdata(wdata),
    .mask_shift(mask_shift), .mask_reset(mask_reset),
    .rdata(rdata), .data_valid(data_valid), .hit(hit), .not_find(not_find),
    .multi_hit(multi_hit), .hit_index(hit_index), .full(full), .full_reject(full_reject),
    .count(count), .mask(mask), .mask_empty(mask_empty)
  );

  always #5 clk = ~clk;

  integer pass = 0, fail = 0;
  task check(input cond, input [8*80-1:0] msg);
    begin
      if (cond) pass = pass + 1;
      else begin fail = fail + 1; $display("FAIL: %0s", msg); end
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

  reg          s_hit, s_multi;
  reg [EB-1:0] s_idx;
  reg [DW-1:0] s_data;

  task do_write(input [BW-1:0] a, input [DW-1:0] d);
    begin @(negedge clk); addr = a; wdata = d; write = 1; @(negedge clk); write = 0; end
  endtask
  task do_read(input [BW-1:0] a);
    begin
      @(negedge clk); addr = a; read = 1;
      #1; s_hit = hit; s_idx = hit_index; s_multi = multi_hit;
      @(negedge clk); read = 0; s_data = rdata;
    end
  endtask
  task shift_mask; begin @(negedge clk); mask_shift = 1; @(negedge clk); mask_shift = 0; end endtask
  task reset_mask; begin @(negedge clk); mask_reset = 1; @(negedge clk); mask_reset = 0; end endtask

  initial begin
    repeat (2) @(negedge clk); rst_n = 1;

    check(morton2(4'd2, 4'd2) == 8'h0C && morton2(4'd3, 4'd3) == 8'h0F && morton2(4'd5, 4'd6) == 8'h39,
          "M0 morton2 encoding matches the spec's bit order");

    do_write(morton2(4'd3, 4'd3), 8'hA3);   // P = (3,3)
    do_write(morton2(4'd5, 4'd6), 8'hB5);   // Q = (5,6)

    // (2,2) から検索：完全一致は無し、2x2 セル [2..3]x[2..3] に広げると P
    do_read(morton2(4'd2, 4'd2)); check(!s_hit, "M1 (2,2) exact miss");
    shift_mask;                                       // mask = FC → 2x2 セル
    do_read(morton2(4'd2, 4'd2)); check(s_hit && s_idx == 0 && !s_multi, "M1 (2,2) 2x2 cell hits P");
    check(mask == 8'hFC, "M1 mask shifted by 2 bits");

    // (4,4) から検索：2x2 セル [4..5]x[4..5] には Q(5,6) は入らない。4x4 セル [4..7]x[4..7] で当たる
    reset_mask;
    do_read(morton2(4'd4, 4'd4)); check(!s_hit, "M2 (4,4) exact miss");
    shift_mask;
    do_read(morton2(4'd4, 4'd4)); check(!s_hit, "M2 (4,4) 2x2 cell misses Q (y=6 is outside)");
    shift_mask;                                       // mask = F0 → 4x4 セル
    do_read(morton2(4'd4, 4'd4)); check(s_hit && s_idx == 1 && !s_multi, "M2 (4,4) 4x4 cell hits Q only");

    // 8x8 セル [0..7]x[0..7] には P も Q も入る → 多重ヒット、最小インデックス P
    shift_mask;                                       // mask = C0
    do_read(morton2(4'd4, 4'd4)); check(s_hit && s_multi && s_idx == 0, "M3 8x8 cell hits both, P wins");

    // 境界問題：(3,3) と (4,4) は隣だが上位ビットが全部違う。8x8 まで広げないと出会わない
    reset_mask;
    do_read(morton2(4'd4, 4'd4)); check(!s_hit, "M4 boundary: (4,4) exact miss");
    shift_mask; do_read(morton2(4'd4, 4'd4)); check(!s_hit, "M4 boundary: 2x2 still misses P(3,3)");

    $display("tb_morton: %0d passed, %0d failed", pass, fail);
    if (fail == 0) $display("ALL TESTS PASSED");
    $finish;
  end
endmodule
