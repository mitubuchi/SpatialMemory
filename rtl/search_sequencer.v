`timescale 1ns/1ps
// 近傍検索シーケンサー（境界対処 A）。仕様書 6 章「境界問題と対処」。
//
// ホストから start / addr / k_max / mode を受け、段 K = 0 .. k_max について
//   中心セル → 面隣接セル → 角のセル
// の順に top_spatial_memory へ検索を出し、最初に当たったところで止まる。
// マスクは段から直接作る（全 1 << K·DIMS）。mask_register は使わない。
//
// 隣のセルへの移動は、Morton コードのまま軸のビットだけに桁上げを通して作る（デコードしない）:
//   x_plus  = (((m | ~AX) + (1 << p)) & AX) | (m & ~AX)     p = K·DIMS + 軸番号
//   x_minus = (((m &  AX) - (1 << p)) & AX) | (m & ~AX)
// 空間の端で桁あふれしたセルは存在しないので、その問い合わせは飛ばす。
//
// 保証: 段 K-1 で何も無ければチェビシェフ距離 2^(K-1) 以内に点は無い。
//       段 K で見つかった点は距離 2^(K+1) 以内（真の最近傍の高々 4 倍）。
//
// mode: 0 = 中心だけ（境界対処なし）、1 = 面隣接まで（1 + 2·DIMS セル）、2 = 全隣接（3^DIMS セル）
// cell_no: 見つかったセルの番号。軸 a の桁（3 進）が 0 = 中心、1 = +1、2 = -1
//
// 問い合わせは 1 件ずつ（resp_valid を待つ）。CAM セル版（遅延 0）でも BRAM 版（遅延 1）でも同じ。
// busy 中は出さない。
module search_sequencer #(
  parameter BIT_WIDTH  = 32,
  parameter ENTRY_BITS = 8,
  parameter DIMS       = 1        // 1: スカラー、2、3
)(
  input  wire                  clk,
  input  wire                  rst_n,
  // ホスト
  input  wire                  start,
  input  wire [BIT_WIDTH-1:0]  addr,
  input  wire [7:0]            k_max,
  input  wire [1:0]            mode,
  output reg                   done,        // 1 クロック
  output reg                   found,
  output reg  [7:0]            level,
  output reg  [5:0]            cell_no,     // cell は Verilog の予約語
  output reg  [ENTRY_BITS-1:0] hit_index,
  output reg                   multi_hit,
  output reg                   active,      // 検索中（addr / mask をこちらが握っている）
  // メモリー側
  output reg                   q_read,
  output reg  [BIT_WIDTH-1:0]  q_addr,
  output wire [BIT_WIDTH-1:0]  q_mask,
  input  wire                  resp_valid,
  input  wire                  hit,
  input  wire [ENTRY_BITS-1:0] r_hit_index,
  input  wire                  r_multi_hit,
  input  wire                  busy
);
  // ---- 軸マスク ----------------------------------------------------------------
  function [BIT_WIDTH-1:0] axis_mask;
    input integer a;
    integer i;
    begin
      for (i = 0; i < BIT_WIDTH; i = i + 1)
        axis_mask[i] = ((i % DIMS) == a);
    end
  endfunction

  // ---- 状態 ----------------------------------------------------------------------
  localparam S_IDLE = 3'd0, S_ISSUE = 3'd1, S_WAIT = 3'd2, S_NEXT = 3'd3, S_FIN = 3'd4;
  reg [2:0]           state;
  reg [BIT_WIDTH-1:0] base;
  reg [7:0]           kmax_q;
  reg [1:0]           mode_q;
  reg [7:0]           k;            // 段
  reg [1:0]           pass;         // 0: 中心、1: 面、2: 角
  reg [5:0]           digv;         // 軸ごとの 3 進の桁（0 / +1 / -1）。軸 a = digv[2a +: 2]

  // ---- セルのアドレスとあふれ（組み合わせ） --------------------------------------
  integer a;
  reg [BIT_WIDTH-1:0] cur;
  reg [BIT_WIDTH:0]   t;
  reg                 ovf;
  reg [1:0]           nz;           // 0 でない桁の数（3 で飽和）
  integer             p;
  reg [BIT_WIDTH-1:0] ax;
  localparam [BIT_WIDTH-1:0] ONE = 1;

  always @* begin
    cur = base;
    ovf = 1'b0;
    nz  = 2'd0;
    t   = {(BIT_WIDTH+1){1'b0}};
    ax  = {BIT_WIDTH{1'b0}};
    p   = 0;
    for (a = 0; a < DIMS; a = a + 1) begin
      if (digv[2*a +: 2] != 2'd0) begin
        nz = nz + 2'd1;
        p  = k * DIMS + a;
        ax = axis_mask(a);
        if (p >= BIT_WIDTH) begin
          ovf = 1'b1;
        end else if (digv[2*a +: 2] == 2'd1) begin
          t   = {1'b0, cur | ~ax} + (ONE << p);
          if (t[BIT_WIDTH]) ovf = 1'b1;
          cur = (t[BIT_WIDTH-1:0] & ax) | (cur & ~ax);
        end else begin
          t   = {1'b0, cur & ax} - (ONE << p);
          if (t[BIT_WIDTH]) ovf = 1'b1;
          cur = (t[BIT_WIDTH-1:0] & ax) | (cur & ~ax);
        end
      end
    end
  end

  // この段のマスク。K·DIMS が幅を超えたら全 0（何でも一致）
  wire [15:0] shift_amt = k * DIMS;
  assign q_mask = (shift_amt >= BIT_WIDTH) ? {BIT_WIDTH{1'b0}} : ({BIT_WIDTH{1'b1}} << shift_amt);

  // この pass で引くセルか
  wire pass_ok = (pass == 2'd0) ? (nz == 2'd0) :
                 (pass == 2'd1) ? (nz == 2'd1) : (nz >= 2'd2);

  // この段が最後か
  wire last_level = (k >= kmax_q) || (shift_amt >= BIT_WIDTH);

  // 桁の繰り上げ（3 進）
  wire [1:0] d0 = digv[1:0], d1 = digv[3:2], d2 = digv[5:4];
  wire c0 = (d0 == 2'd2);
  wire c1 = c0 & (d1 == 2'd2);
  wire wrapped = (DIMS == 1) ? c0 : (DIMS == 2) ? c1 : (c1 & (d2 == 2'd2));

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= S_IDLE; done <= 1'b0; found <= 1'b0; active <= 1'b0; q_read <= 1'b0;
      level <= 8'd0; cell_no <= 6'd0; hit_index <= {ENTRY_BITS{1'b0}}; multi_hit <= 1'b0;
      base <= {BIT_WIDTH{1'b0}}; kmax_q <= 8'd0; mode_q <= 2'd0; k <= 8'd0; pass <= 2'd0;
      digv <= 6'd0; q_addr <= {BIT_WIDTH{1'b0}};
    end else begin
      done   <= 1'b0;
      q_read <= 1'b0;
      case (state)
        S_IDLE: if (start) begin
          base <= addr; kmax_q <= k_max; mode_q <= mode;
          k <= 8'd0; pass <= 2'd0; digv <= 6'd0;
          found <= 1'b0; active <= 1'b1;
          state <= S_ISSUE;
        end
        S_ISSUE: begin
          if (!pass_ok || ovf) state <= S_NEXT;          // このセルは引かない
          else if (!busy) begin
            q_addr <= cur; q_read <= 1'b1;
            state  <= S_WAIT;
          end
        end
        S_WAIT: if (resp_valid) begin
          if (hit) begin
            found <= 1'b1; level <= k;
            cell_no <= {4'd0, d0} + {4'd0, d1} * 6'd3 + {4'd0, d2} * 6'd9;   // 3 進: 軸 0 の桁 + 3·軸 1 + 9·軸 2
            hit_index <= r_hit_index; multi_hit <= r_multi_hit;
            state <= S_FIN;
          end else state <= S_NEXT;
        end
        S_NEXT: begin
          // セルを 1 つ進める（3 進の繰り上げ）
          digv[1:0] <= c0 ? 2'd0 : d0 + 2'd1;
          if (DIMS >= 2 && c0) digv[3:2] <= (d1 == 2'd2) ? 2'd0 : d1 + 2'd1;
          if (DIMS >= 3 && c1) digv[5:4] <= (d2 == 2'd2) ? 2'd0 : d2 + 2'd1;
          if (!wrapped)            state <= S_ISSUE;                                  // 同じ pass の次のセル
          else if (pass < mode_q)  begin pass <= pass + 2'd1; state <= S_ISSUE; end   // 次の pass（面 → 角）
          else if (!last_level)    begin pass <= 2'd0; k <= k + 8'd1; state <= S_ISSUE; end   // 次の段
          else                     begin found <= 1'b0; state <= S_FIN; end           // 打ち切り
        end
        S_FIN: begin
          done <= 1'b1; active <= 1'b0;
          state <= S_IDLE;
        end
        default: state <= S_IDLE;
      endcase
    end
  end

endmodule
