`timescale 1ns/1ps
// データメモリー。動作記述の同期 SRAM（書き込み・読み出しとも 1 クロック）。
// ASIC ではファンダリの SRAM マクロに置き換える（data_sram_wrapper）。
// 仕様書 4 章。
module data_sram #(
  parameter DATA_WIDTH = 64,
  parameter ENTRY_BITS = 8
)(
  input  wire                  clk,
  input  wire                  we,
  input  wire [ENTRY_BITS-1:0] waddr,
  input  wire [DATA_WIDTH-1:0] wdata,
  input  wire [ENTRY_BITS-1:0] raddr,
  output reg  [DATA_WIDTH-1:0] rdata
);
  reg [DATA_WIDTH-1:0] mem [0:(1<<ENTRY_BITS)-1];

  always @(posedge clk) begin
    if (we) mem[waddr] <= wdata;
    rdata <= mem[raddr];
  end

endmodule
