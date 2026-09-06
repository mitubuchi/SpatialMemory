# 空間メモリー / Spatial Memory

CAMベースのアドレスメモリーと SRAM のデータメモリーを組み合わせた、連想メモリー
アーキテクチャです。マスク付き並列一致とLSBマスクシフトによる近傍検索、
複数CAMアレイのAND条件マッチングを軸にしています。

An associative memory architecture that pairs a CAM-based address memory with a data SRAM:
masked parallel matching, LSB-mask-shift neighbor search, and AND-condition matching across
parallel CAM arrays.

## 構成 / Layout

| 場所 | 内容 |
|---|---|
| [SpatialMemory.md](SpatialMemory.md) | 技術仕様書。アーキテクチャ、動作、RTL、ロードマップ |
| [rtl/](rtl/) | Verilog RTL。`top_spatial_memory.v` がトップ。CAM は `cam_array`（CAM セル版、ASIC の本設計）と `cam_array_bram`（FPGA 向け）を `CAM_IMPL` で切替。`search_sequencer.v` が近傍検索（境界対処 A）を回す |
| [tb/](tb/) | 自己判定のテストベンチ（基本動作 / Morton 近傍 / 並列AND / 近傍検索シーケンサー） |
| [sim/run.py](sim/run.py) | Icarus Verilog でテストベンチを回す（CAM セル版と BRAM 版の両方） |
| [synth/run_synth.py](synth/run_synth.py) | yosys で Xilinx 7 シリーズ向けに合成し、資源量と段数を出す |
| [docs/history.md](docs/history.md) | 開発の経緯。何を見つけてなぜそう直したか |
| [docs/hardware-options.md](docs/hardware-options.md) | 実機実験の選択肢。評価ボードの候補と予算、何が載るか |
| [archive/](archive/) | 2026 年 4 月の企画書（docx）とスライド（pptx）。**現在の仕様とは一致しない。** 記録として残すだけ |

## 3つの核心機構 / Three Core Mechanisms

- **ビット並列比較** — 全エントリを同時にXNOR比較し、エントリ数によらず1クロックで判定
- **LSBマスク近傍検索** — マスクの下位ビットを段階的に0にして検索範囲を 2^K 倍に広げる。
  座標は Morton コードで詰めると、1 ステップで全軸が同時に 1 段粗いセルへ広がる
- **AND条件マッチング** — 複数のCAMアレイで**同じ行**が一致したときだけ出力（次元の同時マッチ）

## シミュレーション / Simulation

Icarus Verilog（`iverilog` / `vvp`）が要ります。Windows では
[OSS CAD Suite](https://github.com/YosysHQ/oss-cad-suite-build/releases) を
`%LOCALAPPDATA%\Programs\oss-cad-suite` に展開すると、`sim/run.py` がそこから見つけます。

```bash
python sim/run.py            # 全テストベンチ × 両実装
python sim/run.py basic      # tb_basic だけ
```

各テストベンチは最後に `ALL TESTS PASSED` を出します。`CAM_IMPL = 0`（CAM セル版）と `1`（BRAM 版）の両方で回ります。

```bash
python synth/run_synth.py --config 32x256x2               # CAM セル版の合成見積もり
python synth/run_synth.py --impl bram --config 32x1024x1  # BRAM 版
```

| テストベンチ | 確かめること |
|---|---|
| `tb_basic` | valid ビット、登録・読み出し・上書き、マスクシフト近傍検索と多重ヒット規則、Write 時の完全一致固定、FULL の拒否と上書き |
| `tb_morton` | 2 次元 Morton コードで 1×1 → 2×2 → 4×4 → 8×8 とセルが広がること、境界問題 |
| `tb_parallel` | 並列 CAM の AND が「行ごと」であること（アレイ単位のフラグ AND では通らない入力） |
| `tb_sequencer` | 近傍検索シーケンサー。`0111`/`1000` が段 0 の隣で出会うこと、面 / 全隣接の差、k_max の打ち切り、空間の端の飛ばし |

## 状態 / Status

仕様書と RTL、テストベンチまで。FPGA 以降は
[ロードマップ](SpatialMemory.md#11-開発ロードマップ--roadmap) を参照してください。
