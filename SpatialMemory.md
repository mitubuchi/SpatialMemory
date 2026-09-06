# 空間メモリー（Spatial Memory）技術仕様書

> **Spatial Memory — Architecture, Mechanism, Advantages & ASIC Design Reference**

---

## 目次 / Table of Contents

1. [概要 / Overview](#1-概要--overview)
2. [アーキテクチャ構造 / Architecture](#2-アーキテクチャ構造--architecture)
3. [アドレスメモリー（CAMアレイ）/ Address Memory](#3-アドレスメモリーcamアレイ--address-memory)
4. [データメモリー / Data Memory](#4-データメモリー--data-memory)
5. [ANDマッチング機構 / AND Matching](#5-andマッチング機構--and-matching)
6. [LSBマスク近傍検索 / LSB Mask Neighbor Search](#6-lsbマスク近傍検索--lsb-mask-neighbor-search)
7. [拡張構成 / Scalable Configuration](#7-拡張構成--scalable-configuration)
8. [従来技術との比較・優位性 / Advantages](#8-従来技術との比較優位性--advantages)
9. [ASIC設計詳細 / ASIC Design](#9-asic設計詳細--asic-design)
10. [C# シミュレーション設計 / C# Simulation](#10-c-シミュレーション設計--c-simulation)
11. [開発ロードマップ / Roadmap](#11-開発ロードマップ--roadmap)

---

## 1. 概要 / Overview

**空間メモリー（Spatial Memory）** は、アドレスメモリー（CAMベースのタグ比較器）とデータメモリー（SRAM）を組み合わせた、独自の**連想メモリーアーキテクチャ**です。

> **Spatial Memory** is a novel associative memory architecture combining a CAM-based address memory (tag comparator) with a data SRAM.

### 解決する課題 / Problem Statement

従来の RAM はアドレスを**指定**してデータを取得する構造であり、以下の問題があります。

| 課題 | 説明 |
|------|------|
| 類似検索が困難 | 入力アドレスに近いエントリを探すには線形スキャンが必要 |
| 多次元検索が非効率 | 複数の特徴でAND条件検索するには多段のロジックが必要 |
| 近傍検索のコスト | ソフトウェアによる近似最近傍探索（ANN）は高コスト |

空間メモリーはこれらを **ハードウェアの並列性** によって1クロックで解決します。

---

## 2. アーキテクチャ構造 / Architecture

```
┌─────────────────────────────────────────────────────┐
│              入力アドレス（N bit）+ マスクレジスタ         │
│              Input Address (N-bit) + Mask Register    │
└────────┬───────────────┬────────────────┬────────────┘
         │               │                │
         ▼               ▼                ▼
┌────────────┐  ┌────────────┐  ┌────────────────────┐
│ CAMアレイ  │  │ CAMアレイ  │  │    CAMアレイ #N    │
│   #1       │  │   #2       │  │  （並列接続で       │
│ (次元1)    │  │ (次元2)    │  │   次元拡張）        │
│ XNOR×Mbit  │  │ XNOR×Mbit  │  │   Parallel expand  │
└─────┬──────┘  └─────┬──────┘  └────────┬───────────┘
   match[0]        match[1]           match[N-1]
         │               │                │
         └───────────────┼────────────────┘
                         ▼
                  ┌─────────────┐
                  │  ANDゲート  │
                  │  AND Gate   │
                  │ 全match AND │
                  └──────┬──────┘
                         │ HIT or NotFind
                         ▼
         ┌───────────────────────────────┐
         │   データメモリー（SRAM群）     │
         │   Data Memory (SRAM blocks)   │
         │ Block#0 ─ Block#1 ─ Block#2  │
         │    （直列接続でデータ幅拡張）  │
         └───────────────┬───────────────┘
                         ▼
              データ出力 / null + NotFind Flag
```

### 構成要素 / Components

| コンポーネント | 役割 | 実装 |
|---|---|---|
| **アドレスメモリー** | ビット並列比較・マッチング | CAMセル（XNOR + マスクOR）アレイ |
| **マスクレジスタ** | 検索範囲の制御 | LSBシフトレジスタ |
| **書き込みカウンター** | 新規エントリ管理 | バイナリカウンター（WR_PTR） |
| **ANDゲートツリー** | 同一行が全次元で一致したかの判定 | 行ごとのANDリダクション |
| **データメモリー** | データの格納と出力 | SRAMマクロ（直列拡張可） |

---

## 3. アドレスメモリー（CAMアレイ）/ Address Memory

### CAMセルの論理構成 / CAM Cell Logic

1ビット分のCAMセルは **XNOR ゲート** と **OR ゲート（マスク適用）** の2段構成です。

```
stored_bit ──┐
             ├─[XNOR]─── match_bit ──┐
input_bit  ──┘                       ├─[OR]─── masked_match
                                     │
mask_bit ──[NOT]── ~mask_bit ────────┘
```

#### 論理式 / Boolean Expressions

```
match_bit    = ~(stored_bit XOR input_bit)   // XNOR: 一致で1
masked_match =  match_bit OR (NOT mask_bit)  // マスクが0なら強制一致
row_match    =  AND(masked_match[0..N-1])    // 全ビットANDで行一致判定
```

> `mask_bit = 0` のビットは比較をスキップ（必ず一致扱い）します。  
> When `mask_bit = 0`, that bit is skipped (always treated as matching).

> ⚠️ マスクの適用は **AND ではなく OR（`~mask_bit` との OR）** です。  
> `match_bit AND mask_bit` にすると、マスクした（無視したい）ビットが不一致になり、  
> 行ANDで必ず落ちます。RTL 実装（9章 `cam_cell`）も `xnor_out | ~mask_bit` です。  
> Masking is an **OR with `~mask_bit`, not an AND**: an AND would force masked-out bits  
> to mismatch and kill `row_match`.

### 動作フロー / Operation Flow

```
1. 入力アドレス（N bit）をCAMアレイの全行に同時ブロードキャスト
   Broadcast input address (N-bit) to ALL rows simultaneously

2. 各行で stored_addr XOR input_addr をビット毎に計算
   Each row computes bit-wise XNOR between stored and input address

3. マスクレジスタでマスクビット=0の位置をスキップ
   Mask register zeroes out positions where mask_bit = 0

4. 全有効ビットのANDを取り row_match を生成（1クロック）
   AND all active bits → row_match generated in 1 clock cycle

5. row_match が立っている行のインデックスが hit_index（複数立てば最小インデックス。6章「多重ヒットの規則」）
   The row index where row_match=1 becomes hit_index (lowest index wins on multiple hits; see §6)
```

### 書き込みカウンター / Write Pointer

```
WR_PTR : N-bit バイナリカウンター
- 新規エントリ書き込み時にインクリメント
- Reset 信号でゼロクリア
- FULL フラグ：WR_PTR が最終エントリに達したとき

WR_PTR: N-bit binary counter
- Increments on each new-entry write
- Zero-cleared by Reset signal
- FULL flag: asserted when WR_PTR reaches last entry
```

---

## 4. データメモリー / Data Memory

### 読み書きルール / Read/Write Rules

#### パターン 1：Read + HIT

```
条件 / Condition : CAM が HIT を出力（row_match = 1）、かつ Read 操作
動作 / Behavior  :
  1. hit_index を RAM のアドレスとして使用
  2. RAM[hit_index] を出力バスに出力
  3. 有効データフラグをアサート
```

#### パターン 2：Write + HIT（上書き）

```
条件 / Condition : CAM が HIT を出力、かつ Write 操作
動作 / Behavior  :
  1. hit_index を RAM のアドレスとして使用
  2. RAM[hit_index] ← 新しいデータ（上書き）
  3. アドレスメモリーは変更なし
  4. WR_PTR は変化しない
```

#### パターン 3：Write + NotFind（新規登録）

```
条件 / Condition : CAM が NotFind を出力、かつ Write 操作
動作 / Behavior  :
  1. CAM[WR_PTR]  ← 入力アドレス（アドレスメモリーへ登録）
  2. RAM[WR_PTR]  ← 入力データ（データメモリーへ登録）
  3. WR_PTR       ← WR_PTR + 1（ポインターを進める）
```

#### パターン 4：Read + NotFind

```
条件 / Condition : CAM が NotFind を出力、かつ Read 操作
動作 / Behavior  :
  1. データ出力バスを null / 0 に設定
  2. NotFind フラグをアサート
  3. （上位ロジックがマスクを広げて再検索可能）
```

### 状態遷移まとめ / State Transition Summary

```
                    ┌─────────┐
      Write Addr    │         │  Write Addr
      + NotFind     │  EMPTY  │  + NotFind
    ──────────────► │  ENTRY  │ ─────────────►  WR_PTR++
                    │         │
                    └─────────┘
                         │
                    Read or Write
                    + HIT
                         │
                         ▼
                    ┌─────────┐
                    │  DATA   │  Write + HIT → Overwrite RAM[hit_index]
                    │  VALID  │  Read  + HIT → Output RAM[hit_index]
                    └─────────┘
```

---

## 5. ANDマッチング機構 / AND Matching

### 並列接続の全一致条件 / All-Match Condition

複数のCAMアレイを並列接続した場合、**同一エントリ（同じ行）がすべてのアレイで一致したときのみ** データが出力されます。

ANDは「アレイごとのHITフラグ」ではなく、**行ごとのマッチベクトル同士**で取ります。

```
row_hit[i] = match[0][i] AND match[1][i] AND ... AND match[N-1][i]   // i = 0 .. NUM_ENTRIES-1
HIT        = OR(row_hit[0 .. NUM_ENTRIES-1])                        // 1行でも残ればHIT
hit_index  = PriorityEncode(row_hit)                                // 複数立てば最小インデックス（6章）
```

> ⚠️ フラグ同士の AND（`match_flag[0] AND match_flag[1] AND ...`）にしてはいけません。  
> アレイ#1が3行目、アレイ#2が7行目で一致しただけでHITになってしまい、  
> **同じエントリで一致したことを保証できず、`hit_index` も一意に決まりません。**  
> ANDing per-array HIT flags would assert HIT even when the arrays matched *different*  
> rows, so the AND must be taken per row.

### 多次元連想検索の例 / Multi-Dimensional Search Example

```
CAMアレイ #1 : 色空間（RGB アドレス 24bit）
CAMアレイ #2 : 形状特徴量（128bit ベクトル）
CAMアレイ #3 : 位置情報（32bit 座標）

→ 3次元すべてに一致したエントリのデータのみが出力される
→ Only entries matching in ALL 3 dimensions are output
```

### 出力条件テーブル / Output Condition Table

判定はすべて **同じ行 i について** 行います。

| CAM #1 の行 i | CAM #2 の行 i | CAM #3 の行 i | 出力 / Output |
|--------|--------|--------|---------------|
| 一致   | 一致   | 一致   | ✅ データ出力（hit_index = i） |
| 一致   | 不一致 | 一致   | ❌ その行は落ちる |
| 不一致 | 一致   | 一致   | ❌ その行は落ちる |
| 不一致 | 不一致 | 不一致 | ❌ その行は落ちる |

> 1つの次元でも不一致なら、その行は候補から外れます。全行が落ちれば NotFind です。  
> A single mismatch in any dimension drops that row; if all rows drop, the result is NotFind.

> アレイごとに一致した行が違う場合（#1は行3だけ一致、#2は行7だけ一致）は、  
> どの行 i を見ても全次元一致にならないため **NotFind** です。

---

## 6. LSBマスク近傍検索 / LSB Mask Neighbor Search

### アルゴリズム / Algorithm

```
mask ← 0xFFFF...FFFF   // 全ビット有効（完全一致モード）

LOOP:
  result ← CAM.Search(input_addr, mask)

  IF result == HIT:
    RETURN data[hit_index]          // データを返して終了

  IF mask == 0x0000...0000:
    RETURN null, NotFind            // 全ビット無視しても見つからず終了

  mask ← mask << D                 // LSB を D ビット 0 にする（D = 次元数。スカラーなら 1）
  GOTO LOOP
```

`D` は 1 ステップで剥がすビット数です。アドレスが単なる数値なら `D = 1`、
後述の Morton コードで D 次元の座標を詰めている場合は `D` にすると、
1 ステップで全軸が同時に 1 段粗くなります。

### 検索範囲の拡大 / Search Range Expansion

```
ステップ 0: mask = 1111 1111 1111 1111  → 完全一致（範囲 = 1点）
ステップ 1: mask = 1111 1111 1111 1110  → LSB 1bit 無視（範囲 ×2）
ステップ 2: mask = 1111 1111 1111 1100  → LSB 2bit 無視（範囲 ×4）
ステップ 3: mask = 1111 1111 1111 1000  → LSB 3bit 無視（範囲 ×8）
   ...
ステップ K: mask = 1111 0000 0000 0000  → LSB K bit 無視（範囲 ×2^K）
```

### 特長 / Key Properties

- **共有プレフィックスが最も長いエントリを優先して発見** します（完全一致から段階的に範囲を広げるため）。  
  Finds the entry sharing the **longest address prefix** first (expands range step by step from exact match).
- 1ステップあたり **1クロック** でCAM検索が完了します。  
  Each step completes **in 1 clock cycle**.
- マスクのシフト量 = **検索精度と速度のトレードオフ** を実装側で制御できます。  
  The shift amount = implementation-controlled **tradeoff between precision and speed**.

### 近傍の意味 / What "Neighbor" Means

LSB マスクで広がるのは **上位ビットを共有する範囲（プレフィックス近傍）** です。
ハミング距離（異なるビットの個数）の近さではありません。

```
検索アドレス : 0101 1010
エントリ A   : 0101 1011   ← 下位 1 bit だけ違う   → ステップ 1 で見つかる
エントリ B   : 1101 1010   ← 上位 1 bit だけ違う   → マスクが全 0 になるまで見つからない
```

A と B はどちらもハミング距離 1 ですが、見つかる順は大きく違います。
アドレスを数値と見れば、ステップ K で当たるのは **`2^K` 刻みのブロックで同じ区画に入るエントリ**
であり、これは 1 次元なら数直線上の区間、多次元なら四分木・八分木のセルにあたります。
「近傍」をこの意味で使うことを前提に設計します。

> The mask expands a **shared-prefix neighborhood**, not a Hamming-distance one. At step K the
> hit set is "entries in the same `2^K`-aligned block" — an interval on a number line, or a
> quadtree/octree cell in multiple dimensions.

### 座標データの登録：Morton コード / Morton (Z-order) Encoding

D 次元の座標を扱うときは、各軸のビットを**交互に並べた Morton コード（Z オーダー）**を
アドレスとして記憶します。こうすると LSB を D ビット剥がすごとに、全軸が同時に 1 段粗い
セルに広がります。

```
2 次元、各軸 4 bit の例 / 2-D, 4 bits per axis
  x = x3 x2 x1 x0
  y = y3 y2 y1 y0
  addr = y3 x3 y2 x2 y1 x1 y0 x0        // MSB 側から (y,x) を交互に

ステップ 0: mask = 1111 1111  → 1×1 のセル（完全一致）
ステップ 1: mask = 1111 1100  → 2×2 のセル（x0,y0 を無視）
ステップ 2: mask = 1111 0000  → 4×4 のセル
ステップ 3: mask = 1100 0000  → 8×8 のセル
```

- 1 ステップ = `mask << D`（`mask_register` の `SHIFT_STEP` パラメーター）
- 軸ごとに別の CAM アレイを持たせる並列構成（5章・7章）とも両立します。
  その場合は各アレイが独立のマスクを持ち、軸ごとに広げ方を変えられます。
- 3 次元なら `z y x` を交互に並べ、`D = 3`。

> Interleave the axis bits (Morton / Z-order) before storing. Each shift of D bits then
> coarsens the cell in every axis at once: 1×1 → 2×2 → 4×4 → …

### 境界問題と対処 / Boundary Problem

プレフィックス近傍には、四分木と同じ **境界問題** があります。

```
検索アドレス : 0111
エントリ C   : 1000   ← 数値としては隣（差 1）だが、上位ビットが全部違う
```

C はマスクを全部剥がすまで見つかりません。セルの境界をまたぐ相手は、
どれだけ近くても同じセルには入らないためです。対処は 2 通りあります。

| 方式 | やること | 利点 | 代償 |
|---|---|---|---|
| **A. 検索側をずらす（既定）** | ステップ K で `addr` に加えて、各軸の座標を `± 2^K` ずらして再エンコードしたアドレス（スカラーなら `addr ± 2^K`）を同じマスクで検索する | データを重複させない。登録は変えなくてよい | 検索回数が増える。D 次元で全隣接セルを見るなら `3^D` 回（2D: 9 回、3D: 27 回）。面で接するセルだけなら `2D + 1` 回 |
| **B. 登録側を重ねる** | セルの境界ぎわのエントリを隣のセルにも登録する | 検索は 1 回で済む | エントリを消費する。上書き（Write + HIT）が複数行に及ぶ |

既定は **A** とします。ハードウェアではずらしたアドレスの検索を並列に走らせる
（CAM を複数本持つ、または 1 本を `2D + 1` クロック回す）ことで、追加コストを
サイクル数かアレイ数のどちらかに寄せられます。B はエントリ数に余裕があり、
かつ更新が少ないデータ向けです。

> Prefix neighborhoods split at cell boundaries (`0111` vs `1000`). Default mitigation:
> at step K also query `addr ± 2^K` per axis (face neighbors: `2D + 1` queries; all
> neighbors: `3^D`). Alternative: register boundary entries in adjacent cells too.

### 多重ヒットの規則 / Multi-Hit Rule

マスクを広げると **複数行が同時に一致する** のが普通です（範囲 `2^K` の中に何件も
入るため）。同じセルの中では、CAM はそれ以上の遠近を区別できません。
どれを `hit_index` にするかは次のとおり決めます。

1. **最小インデックスを採る**（プライオリティエンコーダー）。WR_PTR は昇順に採番するので、
   これは**最も古いエントリ**にあたります。決定的で、回路も最も単純です。
2. `multi_hit` フラグを同時に出す。複数あったことを上位ロジックが知れるようにする。
3. 「最も新しいエントリ」を優先したい場合は、エンコーダーの走査方向を逆にする
   （最大インデックス）。設計パラメーターで切り替えます。

セル内の遠近まで欲しい場合は、`multi_hit` を見た上位ロジックがマスクを 1 段戻して
再検索する（範囲を狭める）か、ヒットした行のアドレスを読み戻して距離を計算します。
これは CAM の外の仕事です。

> Multiple rows will match once the mask widens. `hit_index` is the **lowest matching index**
> (oldest entry, via a priority encoder), with a `multi_hit` flag so the caller knows there
> were more. Highest-index-wins is a parameter option. Ranking within a cell is done outside
> the CAM.

---

## 7. 拡張構成 / Scalable Configuration

### 並列接続：次元拡張 / Parallel: Dimension Expansion

```
┌──────────┐  ┌──────────┐  ┌──────────┐
│ CAM #1   │  │ CAM #2   │  │ CAM #3   │
│ (dim 1)  │  │ (dim 2)  │  │ (dim 3)  │
│ 独立した  │  │ 独立した  │  │ 独立した  │
│ アドレス  │  │ アドレス  │  │ アドレス  │
│ 空間      │  │ 空間      │  │ 空間      │
└────┬─────┘  └────┬─────┘  └────┬─────┘
     │match[0]     │match[1]     │match[2]
     └─────────────┴─────────────┘
                   │ AND
                   ▼ HIT（全次元一致のみ）
```

- 各CAMアレイが異なる特徴量の次元を担当。  
- AND条件で「すべての次元でマッチ」したエントリのみ出力。

### 直列接続：データ幅拡張 / Serial: Data Width Expansion

```
SRAM Block #0 ──→ SRAM Block #1 ──→ SRAM Block #2
[bit 0..31]        [bit 32..63]       [bit 64..95]

出力 = {Block#2[95:64], Block#1[63:32], Block#0[31:0]}
```

- 各SRAMブロックのデータ出力を**連結**してバス幅を拡張。  
- ファンダリの標準SRAMマクロ幅（通常32/64bit）を超えるデータに対応。

---

## 8. 従来技術との比較・優位性 / Advantages

### 比較表 / Comparison Table

| 特性 | 従来 RAM | 従来 CAM | **空間メモリー** |
|------|---------|---------|-----------------|
| 検索方式 | アドレス指定 | 完全一致並列 | **マスク付き並列** |
| 近傍検索 | 線形スキャン O(N) | 不可 | **O(K) ※Kはビット差** |
| 多次元 AND 検索 | ソフト多段処理 | 不可 | **1クロック並列** |
| 書き込み管理 | 手動アドレス指定 | 手動アドレス指定 | **カウンター自動管理** |
| データ幅拡張 | バス幅依存 | バス幅依存 | **直列接続で自由拡張** |
| 次元拡張 | 不可 | 不可 | **並列接続で多次元化** |

### 優位性詳細 / Detailed Advantages

#### ① 1クロック完全一致検索
全エントリを**並列**にビット比較するため、エントリ数Nに関わらず検索時間は一定です。  
ソフトウェア実装では O(N) かかる処理が O(1) になります。

#### ② 近傍検索のハードウェア高速化
LSBマスクシフトにより、**共有プレフィックスが最も長いエントリから順に**発見できます。  
Morton コードで座標を詰めておけば、四分木・八分木の「同じセルに入る点を探す」処理を
1 セル 1 クロックでこなせます。ソフトウェアでツリーを辿る場合と違い、セルの中の
エントリ数に検索時間が依存しません（6章「近傍の意味」「境界問題」を参照）。

#### ③ 多次元連想検索
並列CAMアレイのAND条件により、複数の特徴量を**同時にマッチング**できます。  
データベースのマルチインデックス検索に相当する処理を、1クロックで完結できます。

#### ④ スケーラブルな設計
- **並列拡張** → 次元数を増やせる（アドレス空間×次元の乗積で表現力が指数的に増加）
- **直列拡張** → データ幅を自由に増やせる（SRAMマクロの制約を超える）

#### ⑤ 低消費電力
マスクで無効化したビットのCAMセルをクロックゲーティングで停止できるため、  
近傍検索の初期ステップ（完全一致モード）では比較器の大部分が動作します。  
範囲を広げるステップでも**必要なビットのみ**活性化できます。

---

## 9. ASIC設計詳細 / ASIC Design

### RTLモジュール構成 / RTL Module Hierarchy

```
top_spatial_memory.v              ← トップレベル統合
├── cam_array.v                   ← CAMアレイ（N行×Mbit）
│   └── cam_row.v                 ← 1行分のCAMセル群
│       └── cam_cell.v            ← 1ビット比較器（XNOR + マスクOR）
├── mask_register.v               ← LSBシフトマスクレジスタ
├── and_reduction_tree.v          ← 行ごとの全次元AND（行マッチベクトルのAND）
├── priority_encoder.v            ← row_hit → hit_index（多重ヒット時は最小インデックス）
├── wr_pointer.v                  ← 書き込みカウンター（WR_PTR）
├── output_ctrl.v                 ← 出力制御ロジック（HIT/NotFind判定）
└── data_sram_wrapper.v           ← SRAMマクロ ラッパー（直列接続対応）
```

### CAMセル RTL（Verilog）/ CAM Cell RTL

```verilog
module cam_cell (
  input  wire clk,
  input  wire rst_n,
  input  wire we,           // 書き込みイネーブル（行選択済み）
  input  wire input_bit,    // 入力アドレスビット
  input  wire mask_bit,     // マスクビット（0=スキップ）
  output wire match         // 一致フラグ
);
  reg stored_bit;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n)    stored_bit <= 1'b0;
    else if (we)   stored_bit <= input_bit;
  end

  // XNOR: 一致で1、不一致で0
  wire xnor_out = ~(stored_bit ^ input_bit);

  // マスクが0なら強制的に一致（mask_bit=0 → match=1）
  assign match = xnor_out | ~mask_bit;

endmodule
```

### CAM行 RTL / CAM Row RTL

```verilog
module cam_row #(
  parameter BIT_WIDTH  = 32,
  parameter ENTRY_BITS = 8,
  parameter ROW_INDEX  = 0    // この行のインデックス（cam_array が generate で与える）
)(
  input  wire                  clk,
  input  wire                  rst_n,
  input  wire                  we,          // アレイ共通の書き込みイネーブル
  input  wire [ENTRY_BITS-1:0] wr_ptr,      // 書き込み先の行（WR_PTR）
  input  wire [BIT_WIDTH-1:0]  input_addr,
  input  wire [BIT_WIDTH-1:0]  mask,
  output wire                  row_match
);
  wire [BIT_WIDTH-1:0] cell_match;

  // 行選択：WR_PTR が自分の行を指しているときだけ書き込む。
  // これが無いと we で全行が同じアドレスに書き換わる。
  wire we_row = we & (wr_ptr == ROW_INDEX);

  genvar i;
  generate
    for (i = 0; i < BIT_WIDTH; i = i+1) begin : CELL
      cam_cell u_cell (
        .clk       (clk),
        .rst_n     (rst_n),
        .we        (we_row),
        .input_bit (input_addr[i]),
        .mask_bit  (mask[i]),
        .match     (cell_match[i])
      );
    end
  endgenerate

  // 全ビットAND → 行一致
  assign row_match = &cell_match;

endmodule
```

`cam_array` は各行を generate で並べ、`ROW_INDEX` に行番号を与えつつ
`we` と `wr_ptr` を全行へブロードキャストします。書き込みが当たるのは
`wr_ptr` が指す1行だけです。

```verilog
  for (r = 0; r < NUM_ENTRIES; r = r+1) begin : ROW
    cam_row #(.BIT_WIDTH(BIT_WIDTH), .ENTRY_BITS(ENTRY_BITS), .ROW_INDEX(r)) u_row (
      .clk(clk), .rst_n(rst_n), .we(we), .wr_ptr(wr_ptr),
      .input_addr(input_addr), .mask(mask), .row_match(match_vec[r])
    );
  end
```

### ANDリダクションツリー / AND Reduction Tree

```verilog
module and_reduction_tree #(
  parameter NUM_ARRAYS  = 4,    // 並列CAMアレイ数（次元数）
  parameter NUM_ENTRIES = 256   // エントリ数（行数）
)(
  // 各アレイの行マッチベクトルを連結したもの（アレイ a の行 i = match_vec[a*NUM_ENTRIES + i]）
  input  wire [NUM_ARRAYS*NUM_ENTRIES-1:0] match_vec,
  output wire [NUM_ENTRIES-1:0]            row_hit,     // 全次元で一致した行
  output wire                              global_hit,  // 1行でも残ればHIT
  output wire                              not_find     // 未発見フラグ
);
  genvar i, a;
  generate
    for (i = 0; i < NUM_ENTRIES; i = i+1) begin : ROW
      wire [NUM_ARRAYS-1:0] dim_match;
      for (a = 0; a < NUM_ARRAYS; a = a+1) begin : ARR
        assign dim_match[a] = match_vec[a*NUM_ENTRIES + i];
      end
      // 同じ行が全次元で一致したときだけ 1（フラグ同士のANDではない）
      assign row_hit[i] = &dim_match;
    end
  endgenerate

  assign global_hit = |row_hit;
  assign not_find   = ~global_hit;
endmodule
```

### プライオリティエンコーダー / Priority Encoder

`row_hit` から `hit_index` を作ります。複数行が立っているときは **最小インデックス**
（最も古いエントリ）を採り、`multi_hit` を立てます（6章「多重ヒットの規則」）。

```verilog
module priority_encoder #(
  parameter NUM_ENTRIES = 256,
  parameter ENTRY_BITS  = 8,
  parameter NEWEST_WINS = 0     // 1 にすると最大インデックス（最も新しいエントリ）を採る
)(
  input  wire [NUM_ENTRIES-1:0] row_hit,
  output reg  [ENTRY_BITS-1:0]  hit_index,
  output wire                   multi_hit    // 2 行以上一致
);
  integer i;
  always @* begin
    hit_index = {ENTRY_BITS{1'b0}};
    if (NEWEST_WINS) begin
      for (i = 0; i < NUM_ENTRIES; i = i+1)        // 上から上書きして最大インデックスが残る
        if (row_hit[i]) hit_index = i[ENTRY_BITS-1:0];
    end else begin
      for (i = NUM_ENTRIES-1; i >= 0; i = i-1)     // 下から上書きして最小インデックスが残る
        if (row_hit[i]) hit_index = i[ENTRY_BITS-1:0];
    end
  end

  // 最下位の 1 を消して、まだ 1 が残っていれば多重ヒット
  assign multi_hit = |(row_hit & (row_hit - 1'b1));
endmodule
```

上のループ記述は動作定義用です。エントリ数が大きいときは、合成時にツリー構造の
エンコーダー（log2 段）へ置き換えて遅延を抑えます。

### マスクレジスタ / Mask Register

```verilog
module mask_register #(
  parameter BIT_WIDTH  = 32,
  parameter SHIFT_STEP = 1     // 1 ステップで剥がすビット数（Morton コードなら次元数 D）
)(
  input  wire                  clk,
  input  wire                  rst_n,
  input  wire                  shift_en,    // LSBシフト実行
  input  wire                  reset_mask,  // マスクをリセット（全1）
  output reg  [BIT_WIDTH-1:0]  mask,
  output wire                  mask_empty   // マスクが全0（検索終了）
);
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n)          mask <= {BIT_WIDTH{1'b1}};
    else if (reset_mask) mask <= {BIT_WIDTH{1'b1}};
    else if (shift_en)   mask <= mask << SHIFT_STEP;  // LSB を SHIFT_STEP ビット 0 にする
  end

  assign mask_empty = (mask == {BIT_WIDTH{1'b0}});
endmodule
```

### 書き込みポインター / Write Pointer

```verilog
module wr_pointer #(
  parameter ENTRY_BITS = 8   // エントリ数 = 2^ENTRY_BITS
)(
  input  wire                  clk,
  input  wire                  rst_n,
  input  wire                  inc,      // インクリメント
  output reg  [ENTRY_BITS-1:0] wr_ptr,
  output wire                  full      // メモリーフル
);
  reg [ENTRY_BITS-1:0] max_ptr;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n)    wr_ptr <= 0;
    else if (inc)  wr_ptr <= wr_ptr + 1;
  end

  assign full = (wr_ptr == {ENTRY_BITS{1'b1}});
endmodule
```

### タイミング仕様 / Timing Specification

```
Read（完全一致）:
  t_search = 1 clock cycle           // CAM検索（組み合わせ論理）
  t_read   = 1 clock cycle           // SRAM読み出し
  合計 / Total: 2 clock cycles

Write（新規）:
  t_search = 1 clock cycle           // CAM検索
  t_write  = 1 clock cycle           // CAM + SRAM 同時書き込み
  t_inc    = 1 clock cycle           // WR_PTR インクリメント
  合計 / Total: 3 clock cycles

近傍検索（Kビット差）:
  t_neighbor = (K+1) × 2 clock cycles   // K回のマスクシフト + 検索
```

### 設計パラメーター / Design Parameters

| パラメーター | 説明 | 典型値 |
|---|---|---|
| `BIT_WIDTH` | アドレスビット幅 | 32 / 64 / 128 |
| `NUM_ENTRIES` | CAMエントリ数 | 256 / 1024 / 4096 |
| `NUM_ARRAYS` | 並列CAMアレイ数（次元数） | 1〜8 |
| `DATA_WIDTH` | データビット幅（直列拡張後） | 32〜512 |
| `SRAM_WIDTH` | SRAMマクロ1本のビット幅 | 32 / 64 |

### ASIC設計フロー / ASIC Design Flow

```
Step 1: RTL設計（Verilog/SystemVerilog）
        ├── cam_cell, cam_row, cam_array
        ├── mask_register, wr_pointer
        └── top_spatial_memory

Step 2: 機能シミュレーション
        ├── ModelSim / Verilator
        ├── 単体テスト（各モジュール）
        └── 統合テスト（read/write/neighbor search）

Step 3: FPGAプロトタイプ（早期検証）
        ├── Xilinx Vivado（Artix-7 / UltraScale）
        ├── Intel Quartus（Cyclone V / Agilex）
        └── LUTベースのCAMセル実装

Step 4: 論理合成
        ├── Synopsys Design Compiler
        ├── タイミング制約（SDC）設定
        └── ゲートレベルネットリスト生成

Step 5: 配置配線（P&R）
        ├── Cadence Innovus
        ├── SRAMマクロ配置
        ├── タイミングクロージャ
        └── DRC / LVS サインオフ

Step 6: テープアウト
        ├── GDS2 生成
        ├── ファンダリ提出（TSMC / GlobalFoundries等）
        └── シリコン評価・特性測定
```

### 面積・電力見積もり（参考）/ Area & Power Estimate

```
プロセス: TSMC 28nm HPC+（参考値）
構成: BIT_WIDTH=32, NUM_ENTRIES=256, NUM_ARRAYS=2

CAMアレイ:
  エントリ数 256 × ビット幅 32 × 2次元
  = 16,384 CAMセル
  ≈ 約 0.05 mm² @ 28nm

データSRAM:
  256エントリ × 64bit
  ≈ SRAMコンパイラー出力による（約 0.02 mm²）

消費電力（推定）:
  待機時（クロックゲーティング有効）: < 1 mW
  動作時（完全一致検索 @ 500MHz）: 約 50〜100 mW
```

---

## 10. C# シミュレーション設計 / C# Simulation

### ソリューション構成 / Solution Structure

```
SpatialMemory.sln
├── SpatialMemory.Core        (.Net Standard 2.0)
│   ├── CamCell.cs            1ビット比較器
│   ├── CamRow.cs             1行分のCAMセル群
│   ├── CamArray.cs           N行×Mビット CAMアレイ
│   ├── MaskRegister.cs       LSBシフトマスク管理（シフト量 D）
│   ├── MortonCode.cs         座標 ⇄ Morton コード変換（2D / 3D）
│   ├── PriorityEncoder.cs    row_hit → hit_index（最小インデックス）
│   ├── WrPointer.cs          書き込みポインター
│   ├── DataMemory.cs         データRAM + RW制御
│   └── SpatialMemory.cs      トップレベル統合クラス
│
├── SpatialMemory.TestApp     (.Net Forms — テストUI)
│   ├── MainForm.cs
│   ├── SearchPanel.cs
│   └── WritePanel.cs
│
└── SpatialMemory.Tests       (xUnit テスト)
    ├── CamCellTests.cs
    ├── SearchTests.cs
    └── NeighborSearchTests.cs
```

### コアクラス設計（概要）/ Core Class Design

```csharp
// トップレベルAPI
public class SpatialMemory<TData>
{
    // Read: アドレスで検索してデータを返す（近傍検索対応）
    public SearchResult<TData> Read(ulong address, int maxMaskShift = 0);

    // Write: アドレスが存在すれば上書き、なければ新規登録
    public void Write(ulong address, TData data);

    // 近傍検索: LSBシフトしながら、共有プレフィックスが最も長いエントリを探す
    // （プレフィックス近傍。境界問題の対処 A を含む。6章を参照）
    public SearchResult<TData> SearchNearest(ulong address, int maxShift);

    // プロパティ
    public bool IsFull { get; }
    public int EntryCount { get; }
    public int BitWidth { get; }
}

public record SearchResult<TData>(
    bool Hit,
    TData? Data,
    int HitIndex,
    int MaskShifts,  // 何回シフトで見つかったか（＝プレフィックスを何ビット削ったか）
    bool MultiHit    // 同じマスクで複数行が一致した（hit_index は最小インデックス）
);
```

### Unity 3D サポート / Unity 3D Support

`.Net Standard 2.0` ベースのため、Unity の `.asmdef` でそのまま利用可能です。  
将来的に **Unity Package Manager 対応パッケージ** として提供予定。

---

## 11. 開発ロードマップ / Roadmap

| フェーズ | 内容 | 期間 | 状態 |
|---|---|---|---|
| **Ph.0** | アーキテクチャ設計・本仕様書策定 | 完了 | ✅ Done |
| **Ph.1** | C# コアライブラリ実装・ユニットテスト | 2〜3ヶ月 | 🔵 Planning |
| **Ph.2** | .Net Forms テストアプリ・統合テスト | 1〜2ヶ月 | 🔵 Planning |
| **Ph.3** | Verilog RTL 設計・シミュレーション | 2〜3ヶ月 | 🔵 Planning |
| **Ph.4** | FPGA プロトタイプ（Vivado / Quartus） | 2〜3ヶ月 | 🔵 Planning |
| **Ph.5** | 論理合成・タイミング検証 | 2ヶ月 | 🔵 Planning |
| **Ph.6** | P&R・DRC/LVS サインオフ | 2〜3ヶ月 | 🔵 Planning |
| **Ph.7** | テープアウト・シリコン評価 | 3〜6ヶ月 | 🔵 Planning |
| **Ph.8** | IP コア化・Unity パッケージ化 | 未定 | ⚪ Future |

---

## ライセンス / License

本仕様書および設計は社内技術資料です。外部公開・二次利用は別途承認を要します。  
This document is internal technical material. External disclosure requires separate approval.

---

*最終更新 / Last updated: 2026-09-06*  
*作成 / Author: 空間メモリー設計チーム / Spatial Memory Design Team*
