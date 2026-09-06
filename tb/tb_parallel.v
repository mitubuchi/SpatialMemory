// 並列 CAM アレイ（2 次元）の AND が「行ごと」に取れていることの確認。
//   アレイ #1 が行 0、アレイ #2 が行 1 で一致する入力は NotFind でなければならない。
//   アレイ単位の HIT フラグ同士を AND する実装だと、ここが HIT になってしまう。
// 仕様書 5 章。
`timescale 1ns/1ps
module tb_parallel;
  localparam BW = 8, EB = 2, DW = 8, NA = 2;

  reg              clk = 0, rst_n = 0;
  reg              read = 0, write = 0, mask_shift = 0, mask_reset = 0;
  reg  [NA*BW-1:0] addr = 0;
  reg  [DW-1:0]    wdata = 0;
  wire [DW-1:0]    rdata;
  wire             data_valid, hit, not_find, multi_hit, full, full_reject, mask_empty;
  wire [EB-1:0]    hit_index;
  wire [EB:0]      count;
  wire [BW-1:0]    mask;

  top_spatial_memory #(.BIT_WIDTH(BW), .ENTRY_BITS(EB), .NUM_ARRAYS(NA), .DATA_WIDTH(DW)) dut (
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

  reg          s_hit;
  reg [EB-1:0] s_idx;
  reg [DW-1:0] s_data;

  // アレイ 0 = addr[7:0]、アレイ 1 = addr[15:8]
  task do_write(input [BW-1:0] a0, input [BW-1:0] a1, input [DW-1:0] d);
    begin @(negedge clk); addr = {a1, a0}; wdata = d; write = 1; @(negedge clk); write = 0; end
  endtask
  task do_read(input [BW-1:0] a0, input [BW-1:0] a1);
    begin
      @(negedge clk); addr = {a1, a0}; read = 1;
      #1; s_hit = hit; s_idx = hit_index;
      @(negedge clk); read = 0; s_data = rdata;
    end
  endtask

  initial begin
    repeat (2) @(negedge clk); rst_n = 1;

    do_write(8'd1, 8'd1, 8'hA1);   // 行 0: (1, 1)
    do_write(8'd2, 8'd2, 8'hB2);   // 行 1: (2, 2)
    check(count == 2, "P0 two entries");

    do_read(8'd1, 8'd1); check(s_hit && s_idx == 0 && s_data == 8'hA1, "P1 (1,1) hits row 0");
    do_read(8'd2, 8'd2); check(s_hit && s_idx == 1 && s_data == 8'hB2, "P1 (2,2) hits row 1");

    // アレイ 0 は行 0 で、アレイ 1 は行 1 で一致する。同じ行では一致しないので NotFind
    do_read(8'd1, 8'd2); check(!s_hit, "P2 (1,2): per-array flags would AND to HIT; per-row AND must miss");
    do_read(8'd2, 8'd1); check(!s_hit, "P2 (2,1): same");

    // 片方の次元だけ一致
    do_read(8'd1, 8'd9); check(!s_hit, "P3 one dimension only");

    $display("tb_parallel: %0d passed, %0d failed", pass, fail);
    if (fail == 0) $display("ALL TESTS PASSED");
    $finish;
  end
endmodule
