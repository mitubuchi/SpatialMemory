# 空間メモリー / Spatial Memory

CAMベースのアドレスメモリーと SRAM のデータメモリーを組み合わせた、連想メモリー
アーキテクチャの設計資料です。マスク付き並列一致とLSBマスクシフトによる近傍検索、
複数CAMアレイのAND条件マッチングを軸にしています。

Design material for an associative memory architecture that pairs a CAM-based address
memory with a data SRAM: masked parallel matching, LSB-mask-shift neighbor search, and
AND-condition matching across parallel CAM arrays.

> 本リポジトリは設計資料のみで、RTL / C# の実装はまだ含まれていません。  
> Design documents only — no RTL or C# implementation yet.

## 資料 / Documents

| ファイル | 内容 |
|---|---|
| [SpatialMemory.md](SpatialMemory.md) | 技術仕様書。アーキテクチャ、動作、Verilog RTL、C#シミュレーション設計、ロードマップ |
| `spatial_memory_proposal.docx` | 技術企画書（ASIC化の提案） |
| `spatial_memory_tech_design02.pptx` | 詳細技術設計書（スライド版） |

## 3つの核心機構 / Three Core Mechanisms

- **ビット並列比較** — 全エントリを同時にXNOR比較し、エントリ数によらず1クロックで判定
- **LSBマスク近傍検索** — マスクの下位ビットを段階的に0にして検索範囲を 2^K 倍に広げる
- **AND条件マッチング** — 複数のCAMアレイで**同じ行**が一致したときだけ出力（次元の同時マッチ）

## 状態 / Status

Ph.0（アーキテクチャ設計・仕様書策定）まで完了。Ph.1 以降は
[ロードマップ](SpatialMemory.md#11-開発ロードマップ--roadmap) を参照してください。
