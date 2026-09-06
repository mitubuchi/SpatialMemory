`timescale 1ns/1ps
// N 行 × M ビットの CAM アレイ（BRAM 版。FPGA で大きなエントリ数を試すための差し替え実装）。
//
// 比較器を並べる代わりに「表を引く」。アドレスを SLICE_BITS ビットずつのスライスに切り、
// スライスごとに BRAM を持つ。BRAM の 1 行は NUM_ENTRIES ビットの一致ベクトルで、
//   行 { j, v >> j } の bit i = 1  ⇔  エントリ i のそのスライスの上位 (SLICE_BITS - j) ビットが (v >> j)
// という「プレフィックス表」になっている（j = 0 .. SLICE_BITS-1）。
//
// 検索: グローバルマスクからスライスごとに「LSB 側から剥がされたビット数 m_s」を求め、
//   m_s == SLICE_BITS なら そのスライスは読まず全 1 として扱う（バイパス）
//   それ以外なら         行 { m_s, v_s >> m_s } を 1 回読む
// 全スライスの読み出し結果を行ごとに AND し、valid ビットで未使用行を落とす。
// LSB から順に剥がすという空間メモリーの規則があるので、どの段でも BRAM 読み出しは 1 回で済む。
//
// 登録: エントリ i のアドレスが決まると、bit i を立てるべき行はスライスごと・段ごとに
// ちょうど 1 行。各スライスを並列に、段 j = 0 .. SLICE_BITS-1 で「読む → bit i を立てる → 書き戻す」
// を繰り返す（2 × SLICE_BITS クロック）。その間 busy を出す。
//
// ポートの使い方: 読み出しはポート A だけ（検索も登録中の読み出しも）、ポート B は書き込み専用。
// 両ポートで読むと BRAM が TDP モードになりポート幅が半分（36 bit）に落ちて個数が倍になる。
// 読み 1 / 書き 1 の SDP モードなら 72 bit 幅で使える。busy 中の検索はどのみち保証しないので、
// 登録中はポート A を登録側に貸す。
//
// リセット: BRAM の中身は不定なので、リセット解除後に全行を 0 で埋める（2^(SLICE_BITS+1) クロック、busy）。
//
// 制約:
//   - match_vec は入力の 1 クロック後（LATENCY = 1）
//   - busy 中の検索結果は保証しない（tb は busy を待つ）
//   - 登録は追記のみ。アドレスの変更・削除は無い（仕様書の範囲）。削除を足すなら
//     登録と同じ行を辿って bit i を落とすだけで、同じクロック数で済む
//
// これは FPGA 専用の技法で、ASIC では仕様書どおりの CAM セル（cam_array）が本設計。
module cam_array_bram #(
  parameter BIT_WIDTH  = 32,
  parameter ENTRY_BITS = 8,
  parameter SLICE_BITS = 8
)(
  input  wire                        clk,
  input  wire                        rst_n,
  // 検索
  input  wire [BIT_WIDTH-1:0]        input_addr,
  input  wire [BIT_WIDTH-1:0]        mask,
  output wire [(1<<ENTRY_BITS)-1:0]  match_vec,   // 1 クロック遅れ
  // 登録
  input  wire                        we,
  input  wire [ENTRY_BITS-1:0]       wr_ptr,
  input  wire [BIT_WIDTH-1:0]        wr_addr,
  output reg                         busy
);
  localparam NUM_ENTRIES  = 1 << ENTRY_BITS;
  localparam NS           = (BIT_WIDTH + SLICE_BITS - 1) / SLICE_BITS;   // スライス数
  localparam PW           = NS * SLICE_BITS;                             // パディング後のビット幅
  localparam RB           = SLICE_BITS + 1;                              // 行アドレス幅
  localparam integer ROWS = 1 << RB;                                     // プレフィックス表の行数（使うのは ROWS-2）

  // 端数のスライスは、アドレスを 0、マスクを 1 で埋める（常に一致する）
  wire [PW-1:0] addr_p = {{(PW-BIT_WIDTH){1'b0}}, input_addr};
  wire [PW-1:0] mask_p = {{(PW-BIT_WIDTH){1'b1}}, mask};

  // 段 j、値 v の行アドレス。段 j の先頭 = 2^(k+1) - 2^(k+1-j)
  function [RB-1:0] row_of;
    input integer          j;
    input [SLICE_BITS-1:0] v;
    begin
      row_of = (ROWS - (ROWS >> j)) + (v >> j);
    end
  endfunction

  // マスクの LSB 側から数えて何ビットが 0 か（0 .. SLICE_BITS）
  function integer zeros_below;
    input [SLICE_BITS-1:0] m;
    integer i;
    begin
      zeros_below = SLICE_BITS;
      for (i = SLICE_BITS - 1; i >= 0; i = i - 1)
        if (m[i]) zeros_below = i;
    end
  endfunction

  // ---- valid ビット（FF）---------------------------------------------------
  reg [NUM_ENTRIES-1:0] valid;

  // ---- 登録 / クリアの制御 ---------------------------------------------------
  localparam S_CLR = 2'd0, S_IDLE = 2'd1, S_RD = 2'd2, S_WR = 2'd3;
  reg [1:0]            state;
  reg [RB-1:0]         clr_row;
  reg [PW-1:0]         ins_addr;
  reg [ENTRY_BITS-1:0] ins_ptr;
  reg [3:0]            ins_j;        // 段（SLICE_BITS <= 15）

  wire inserting = (state == S_RD) || (state == S_WR);

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state    <= S_CLR;
      clr_row  <= {RB{1'b0}};
      busy     <= 1'b1;
      valid    <= {NUM_ENTRIES{1'b0}};
      ins_addr <= {PW{1'b0}};
      ins_ptr  <= {ENTRY_BITS{1'b0}};
      ins_j    <= 4'd0;
    end else begin
      case (state)
        S_CLR: begin                      // 全行を 0 で埋める
          clr_row <= clr_row + 1'b1;
          if (clr_row == {RB{1'b1}}) begin
            state <= S_IDLE;
            busy  <= 1'b0;
          end
        end
        S_IDLE: begin
          if (we) begin
            ins_addr <= {{(PW-BIT_WIDTH){1'b0}}, wr_addr};
            ins_ptr  <= wr_ptr;
            ins_j    <= 4'd0;
            busy     <= 1'b1;
            state    <= S_RD;
          end
        end
        S_RD: state <= S_WR;              // 行を読む（ポート A）
        S_WR: begin                       // bit i を立てて書き戻す（ポート B）
          if (ins_j == SLICE_BITS - 1) begin
            valid[ins_ptr] <= 1'b1;       // 全段そろってから有効にする
            busy  <= 1'b0;
            state <= S_IDLE;
          end else begin
            ins_j <= ins_j + 1'b1;
            state <= S_RD;
          end
        end
      endcase
    end
  end

  // ---- スライスごとの表 -------------------------------------------------------
  wire [NS*NUM_ENTRIES-1:0] slice_match;   // スライス s の一致ベクトル = slice_match[s*NUM_ENTRIES +: NUM_ENTRIES]

  genvar s;
  generate
    for (s = 0; s < NS; s = s + 1) begin : SL
      reg [NUM_ENTRIES-1:0] tbl [0:ROWS-1];

      // 検索の行アドレス
      wire [SLICE_BITS-1:0] v_s  = addr_p[s*SLICE_BITS +: SLICE_BITS];
      wire [SLICE_BITS-1:0] m_s  = mask_p[s*SLICE_BITS +: SLICE_BITS];
      integer zb;
      always @* zb = zeros_below(m_s);
      wire                  byp   = (zb == SLICE_BITS);
      wire [RB-1:0]         s_row = row_of(zb, v_s);

      // 登録の行アドレス
      wire [SLICE_BITS-1:0] iv    = ins_addr[s*SLICE_BITS +: SLICE_BITS];
      wire [RB-1:0]         i_row = row_of(ins_j, iv);

      // ポート A（読み出し専用）。登録中は登録側の行を読む
      wire [RB-1:0]          a_row = inserting ? i_row : s_row;
      reg  [NUM_ENTRIES-1:0] a_q;
      reg                    byp_q;
      always @(posedge clk) begin
        a_q   <= tbl[a_row];
        byp_q <= byp;
      end
      assign slice_match[s*NUM_ENTRIES +: NUM_ENTRIES] = byp_q ? {NUM_ENTRIES{1'b1}} : a_q;

      // ポート B（書き込み専用）。クリア中は 0、登録中は読んだ行に bit i を立てて書き戻す
      wire                   b_we    = (state == S_CLR) || (state == S_WR);
      wire [RB-1:0]          b_row   = (state == S_CLR) ? clr_row : i_row;
      wire [NUM_ENTRIES-1:0] b_wdata = (state == S_CLR) ? {NUM_ENTRIES{1'b0}}
                                                        : (a_q | ({{(NUM_ENTRIES-1){1'b0}}, 1'b1} << ins_ptr));
      always @(posedge clk) begin
        if (b_we) tbl[b_row] <= b_wdata;
      end
    end
  endgenerate

  // ---- 行ごとの AND -----------------------------------------------------------
  integer k;
  reg [NUM_ENTRIES-1:0] and_all;
  always @* begin
    and_all = valid;
    for (k = 0; k < NS; k = k + 1) and_all = and_all & slice_match[k*NUM_ENTRIES +: NUM_ENTRIES];
  end
  assign match_vec = and_all;

endmodule
