// 基本動作のテスト（1 次元、16 bit アドレス、8 エントリ）。
//   - リセット直後にアドレス 0 が未使用行に当たらない（valid ビット）
//   - 完全一致の登録 / 読み出し / 上書き
//   - LSB マスクシフトによる近傍検索と多重ヒット規則（最小インデックス）
//   - マスクを広げたまま Write しても近くのエントリを壊さない（4 章 共通規則）
//   - FULL で新規登録を拒否し、上書きは通す
//   - マスクを全部剥がすと全行に当たる
`timescale 1ns/1ps
module tb_basic;
  parameter CAM_IMPL = 0;   // 0: CAM セル版 / 1: BRAM 版（iverilog -P tb_basic.CAM_IMPL=1）
  localparam BW = 16, EB = 3, DW = 16;

  reg           clk = 0, rst_n = 0;
  reg           read = 0, write = 0, mask_shift = 0, mask_reset = 0;
  reg  [BW-1:0] addr = 0;
  reg  [DW-1:0] wdata = 0;
  wire [DW-1:0] rdata;
  wire          data_valid, resp_valid, hit, not_find, multi_hit, full, full_reject, busy, mask_empty;
  wire [EB-1:0] hit_index;
  wire [EB:0]   count;
  wire [BW-1:0] mask;

  top_spatial_memory #(.BIT_WIDTH(BW), .ENTRY_BITS(EB), .NUM_ARRAYS(1), .DATA_WIDTH(DW), .CAM_IMPL(CAM_IMPL)) dut (
    .clk(clk), .rst_n(rst_n), .read(read), .write(write), .addr(addr), .wdata(wdata),
    .mask_shift(mask_shift), .mask_reset(mask_reset),
    .rdata(rdata), .data_valid(data_valid), .resp_valid(resp_valid), .hit(hit), .not_find(not_find),
    .multi_hit(multi_hit), .hit_index(hit_index), .full(full), .full_reject(full_reject),
    .busy(busy), .count(count), .mask(mask), .mask_empty(mask_empty)
  );

  always #5 clk = ~clk;

  integer pass = 0, fail = 0;
  task check(input cond, input [8*80-1:0] msg);
    begin
      if (cond) pass = pass + 1;
      else begin fail = fail + 1; $display("FAIL: %0s", msg); end
    end
  endtask

  // busy が下がるまで待つ（BRAM 版のリセット後クリアと登録中）
  task wait_idle;
    begin #1; while (busy) begin @(negedge clk); #1; end end
  endtask

  // 要求を出した直後に呼ぶ。resp_valid が立つまで待ち、1 クロックで要求を下げる
  task wait_resp;
    begin
      #1;
      if (!resp_valid) begin
        @(negedge clk); read = 0; write = 0; #1;
        while (!resp_valid) begin @(negedge clk); #1; end
      end
    end
  endtask

  // 検索結果のサンプル
  reg          s_hit, s_multi, s_valid, s_reject;
  reg [EB-1:0] s_idx;
  reg [DW-1:0] s_data;

  task do_write(input [BW-1:0] a, input [DW-1:0] d);
    begin
      wait_idle;
      @(negedge clk); addr = a; wdata = d; write = 1;
      wait_resp; s_hit = hit; s_idx = hit_index; s_reject = full_reject;
      @(negedge clk); write = 0;
      wait_idle;                  // BRAM 版は登録に 2 × SLICE_BITS クロックかかる
    end
  endtask

  task do_read(input [BW-1:0] a);
    begin
      wait_idle;
      @(negedge clk); addr = a; read = 1;
      wait_resp; s_hit = hit; s_idx = hit_index; s_multi = multi_hit;
      @(negedge clk); read = 0; s_data = rdata; s_valid = data_valid;
    end
  endtask

  task shift_mask;
    begin @(negedge clk); mask_shift = 1; @(negedge clk); mask_shift = 0; end
  endtask

  task reset_mask;
    begin @(negedge clk); mask_reset = 1; @(negedge clk); mask_reset = 0; end
  endtask

  integer k;
  initial begin
    repeat (2) @(negedge clk); rst_n = 1;

    // T1: 未使用行にアドレス 0 が当たらない
    do_read(16'h0000);
    check(!s_hit && !s_valid, "T1 reset: addr 0 must not hit empty rows");

    // T2: 3 件登録
    do_write(16'h1234, 16'hAAAA);
    do_write(16'h1235, 16'hBBBB);
    do_write(16'h8000, 16'hCCCC);
    check(count == 3, "T2 count == 3");

    // T3: 完全一致で読める
    do_read(16'h1234); check(s_hit && s_idx == 0 && s_valid && s_data == 16'hAAAA, "T3 read A");
    do_read(16'h1235); check(s_hit && s_idx == 1 && s_valid && s_data == 16'hBBBB, "T3 read B");
    do_read(16'h8000); check(s_hit && s_idx == 2 && s_valid && s_data == 16'hCCCC, "T3 read C");

    // T4: 上書きは行を消費しない
    do_write(16'h1234, 16'hA0A0);
    check(s_hit && count == 3, "T4 overwrite hits and keeps count");
    do_read(16'h1234); check(s_data == 16'hA0A0, "T4 read back overwritten data");

    // T5: 無いものは NotFind
    do_read(16'h1236); check(!s_hit && !s_valid, "T5 miss");

    // T6: 近傍検索。0x1236 は 0x1234 / 0x1235 と下位 2 bit の中で違う
    shift_mask;                     // mask = FFFE
    do_read(16'h1236); check(!s_hit, "T6 shift1 still miss (bit1 differs)");
    shift_mask;                     // mask = FFFC
    do_read(16'h1236);
    check(s_hit && s_multi && s_idx == 0 && s_data == 16'hA0A0, "T6 shift2 hits A and B, lowest index wins");

    // T7: マスクを広げたまま Write しても、近くのエントリを壊さない
    do_write(16'h1237, 16'hDDDD);
    check(!s_hit && count == 4, "T7 write under widened mask creates a new entry");
    reset_mask;
    do_read(16'h1234); check(s_hit && s_data == 16'hA0A0, "T7 A untouched");
    do_read(16'h1235); check(s_hit && s_data == 16'hBBBB, "T7 B untouched");
    do_read(16'h1237); check(s_hit && s_idx == 3 && s_data == 16'hDDDD, "T7 new entry readable");

    // T8: 満杯にする
    do_write(16'h0000, 16'h0000);
    do_write(16'h0001, 16'h0001);
    do_write(16'h0002, 16'h0002);
    do_write(16'h0003, 16'h0003);
    check(count == 8 && full, "T8 full after 8 entries");

    // T9: FULL 中の新規登録は拒否
    do_write(16'h0004, 16'h0004);
    check(s_reject && count == 8, "T9 new entry rejected while full");
    do_read(16'h0004); check(!s_hit, "T9 rejected entry is absent");

    // T10: FULL でも上書きは通る
    do_write(16'h0002, 16'h2222);
    check(s_hit && count == 8, "T10 overwrite while full");
    do_read(16'h0002); check(s_data == 16'h2222, "T10 read back");
    do_read(16'h0000); check(s_hit && s_idx == 4 && s_data == 16'h0000, "T10 addr 0 is a real entry now");

    // T11: マスクを全部剥がすと全行に当たる
    for (k = 0; k < BW; k = k + 1) shift_mask;
    check(mask_empty, "T11 mask empty after BW shifts");
    do_read(16'hFFFF); check(s_hit && s_multi && s_idx == 0, "T11 everything matches, lowest index");
    reset_mask;
    check(mask == 16'hFFFF, "T11 mask reset");

    $display("tb_basic: %0d passed, %0d failed", pass, fail);
    if (fail == 0) $display("ALL TESTS PASSED");
    $finish;
  end
endmodule
