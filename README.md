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
| [rtl/](rtl/) | Verilog RTL。`top_spatial_memory.v` がトップ |
| [tb/](tb/) | 自己判定のテストベンチ（基本動作 / Morton 近傍 / 並列AND） |
| [sim/run.py](sim/run.py) | Icarus Verilog でテストベンチを回すスクリプト |
| `spatial_memory_proposal.docx` | 技術企画書（ASIC化の提案） |
| `spatial_memory_tech_design02.pptx` | 詳細技術設計書（スライド版） |

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
python sim/run.py            # 全テストベンチ
python sim/run.py basic      # tb_basic だけ
```

各テストベンチは最後に `ALL TESTS PASSED` を出します。

| テストベンチ | 確かめること |
|---|---|
| `tb_basic` | valid ビット、登録・読み出し・上書き、マスクシフト近傍検索と多重ヒット規則、Write 時の完全一致固定、FULL の拒否と上書き |
| `tb_morton` | 2 次元 Morton コードで 1×1 → 2×2 → 4×4 → 8×8 とセルが広がること、境界問題 |
| `tb_parallel` | 並列 CAM の AND が「行ごと」であること（アレイ単位のフラグ AND では通らない入力） |

## 状態 / Status

仕様書と RTL、テストベンチまで。FPGA 以降は
[ロードマップ](SpatialMemory.md#11-開発ロードマップ--roadmap) を参照してください。
