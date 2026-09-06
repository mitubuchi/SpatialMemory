# 実機実験の選択肢 / Hardware Options for Prototyping

2026-09-07 時点の調査。価格は為替と在庫で動くので、注文時に必ず確認すること。
根拠にした合成結果は [SpatialMemory.md](../SpatialMemory.md) 9 章「FPGA 合成の実測」。

## 前提

いまの設計（32 bit、256〜1024 エントリ）は **Artix-7 クラスの評価ボード 1 枚で載る**。
予算の中心は 1〜5 万円で、書き込み器や測定器は別途要らない（USB JTAG が板に載っており、
中の信号は Vivado の ILA で見られる）。

## デバイスごとに何が載るか

yosys の合成結果（DATA_WIDTH = 64）から。括弧は使用率。

| デバイス | LUT | RAMB36 | CAM セル版 | BRAM 版 |
|---|---|---|---|---|
| XC7A35T | 20,800 | 50 | 32 × 256 × 1（65%） | 32 × 256 × 2（BRAM 66%） |
| XC7A100T | 63,400 | 135 | 32 × 256 × 2（24%） | 32 × 1024 × 1（BRAM 44%） |
| XC7Z020（Zynq） | 53,200 | 140 | 32 × 256 × 2（29%） | 32 × 1024 × 1（BRAM 43%） |
| XC7A200T | 134,600 | 365 | 32 × 1024 × 1（40%） | 32 × 4096 × 1 相当 |

## 選択肢

### ① 最小（1〜2 万円）: Alchitry Au V2 — XC7A35T

- 価格: $99.99（SparkFun / Alchitry 直販）、$112.80（DigiKey）
- USB JTAG / UART 内蔵、256 MB DDR3、I/O 104 本
- 載るもの: 256 エントリの CAM セル版、BRAM 版の 2 次元構成
- 向き: 「設計が本当にシリコンで動くか」を確かめる。仕様書の想定構成（256 × 2 次元の CAM セル版）は入らない

### ② 推奨（4〜5 万円）: Digilent Arty A7-100T — XC7A100T

- 価格: 定価 $249。ただし 2026 年 7 月時点で $314 の掲載もあり、注文時に確認
- DDR3、Ethernet、PMOD × 4、USB UART、Arduino 互換ヘッダー
- 載るもの: 1024 エントリの BRAM 版、2 次元の CAM セル版。**仕様書の想定構成をそのまま実機で測れる**
- 資料と作例が最も多く、行き詰まったときに調べやすい
- ホスト側の口は UART ブリッジ（RTL で 100 行程度）を自作して `start / addr / k_max / mode` を送る

### ②′ 同じ予算の別案: PYNQ-Z2 — Zynq XC7Z020（$150〜200 前後）

- ARM Cortex-A9 が同じチップに載る。**Python から AXI 経由でシーケンサーを叩ける**
- UART ブリッジを自作しなくて済むので、近傍検索の統計（何段で見つかるか、多重ヒットの頻度）を
  大量に取る実験には Arty より向く
- FPGA 部は 100T とほぼ同格

### ③ 大規模（10〜20 万円）: XC7A200T 搭載ボード

- Digilent Nexys Video（$500 前後）、Alinx AX7201 / AX7203（$300〜400）
- 4096 エントリ級や 3 次元構成を試すならここ
- **まず ② で振る舞いを固めてからで十分**

## ソフトウェア

- **Vivado**: Artix-7 / Zynq-7000 は無償版（Standard）で全部使える。Windows で動く。
  インストールに 60〜100 GB。yosys の見積もりを、配置配線後の本当の Fmax で置き換えられる
- OSS CAD Suite にも Xilinx 向けの実験的な流れ（openXC7）はあるが、実機では Vivado を使う
- `rtl/` はそのまま Vivado に読める。板が届いたら UART ブリッジと制約ファイル（.xdc）を足す作業から始める

## 板の他にかかるもの

- 送料・関税・消費税: Digi-Key / Mouser の日本向け直送で、$250 の板なら合計 4.5 万円前後を見ておく
- ロジックアナライザー、外部 JTAG は不要

## その先：本物のシリコン（目安のみ）

価格帯の変動が大きいので、着手するときに改めて確認すること。

| 経路 | 規模 | 費用の目安 | 用途 |
|---|---|---|---|
| Tiny Tapeout | タイル 1 枚（極小） | $50〜300 | 16 × 16 程度の CAM を載せて「セルが動く」ことを確かめる |
| Efabless chipIgnite（SKY130） | 10 mm² 級 | 1 万ドル前後 | 数百エントリの CAM を実シリコンで |
| 28 nm MPW | 本命 | 桁が 2 つ上 | 企画書の段階では FPGA 実測を根拠に置くのが現実的 |

## 結論

まず **Arty A7-100T か PYNQ-Z2 を 1 枚（4〜5 万円）**。統計を大量に取るなら PYNQ-Z2、
資料の多さと PMOD の拡張性を取るなら Arty A7-100T。

## 出典

- [Digilent Arty A7-100T（直販）](https://digilent.com/shop/arty-a7-100t-artix-7-fpga-development-board/)
- [TEquipment Arty A7-100T](https://www.tequipment.net/Digilent/Arty-A7-100T/FPGA/)
- [DigiKey Arty A7-100T](https://www.digikey.com/en/products/detail/digilent-inc/410-319-1/9445912)
- [SparkFun Alchitry Au V2](https://www.sparkfun.com/alchitry-au-v2.html)
- [DigiKey Alchitry Au V2](https://www.digikey.com/en/products/detail/sparkfun-electronics/27874/26266379)
- [Alchitry Au V2（直販）](https://shop.alchitry.com/products/alchitry-au)
