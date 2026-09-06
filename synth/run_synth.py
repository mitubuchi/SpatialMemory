#!/usr/bin/env python3
"""yosys で top_spatial_memory を Xilinx 7 シリーズ向けに合成し、資源量と論理段数を出す。

    python synth/run_synth.py                 # 既定の構成を全部
    python synth/run_synth.py --config 32x256x1

構成は BIT_WIDTH x NUM_ENTRIES x NUM_ARRAYS で指定する（DATA_WIDTH は --data、既定 64）。
結果は synth/out/<構成>.log に yosys の全出力、標準出力に要約を出す。
FPGA の実配線遅延は入っていない。LUT depth はレジスタ / BRAM ポート間の最長経路に並ぶセル数
（LUT / CARRY4 / MUXF / 分散RAM を各 1 と数える）で、おおまかな比較のための値。
正確な Fmax は Vivado で取る。
"""
import argparse
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RTL = ROOT / "rtl"
OUT = ROOT / "synth" / "out"

CANDIDATE_BINS = [
    Path(os.environ.get("LOCALAPPDATA", "")) / "Programs" / "oss-cad-suite" / "bin",
    Path(os.environ.get("OSS_CAD_SUITE", "")) / "bin",
]

DEFAULT_CONFIGS = ["16x64x1", "32x256x1", "32x256x2", "32x1024x1"]


def find_yosys():
    for d in CANDIDATE_BINS:
        p = d / "yosys.exe"
        if p.is_file():
            root = d.parent
            os.environ["PATH"] = os.pathsep.join(
                [str(root / "bin"), str(root / "lib"), os.environ.get("PATH", "")])
            return str(p)
    return "yosys"


def parse_config(cfg):
    m = re.fullmatch(r"(\d+)x(\d+)x(\d+)", cfg)
    if not m:
        sys.exit(f"bad config: {cfg} (expected BITxENTRIESxARRAYS)")
    bw, ne, na = map(int, m.groups())
    if ne & (ne - 1):
        sys.exit(f"NUM_ENTRIES must be a power of two: {ne}")
    return bw, ne, na, ne.bit_length() - 1


def synth(cfg, data_width, yosys, impl):
    bw, ne, na, eb = parse_config(cfg)
    OUT.mkdir(parents=True, exist_ok=True)
    cam_impl = 1 if impl == "bram" else 0
    cfg = f"{cfg}.{impl}"
    log = OUT / f"{cfg}.log"
    ys = OUT / f"{cfg}.ys"
    sources = " ".join(str(p).replace("\\", "/") for p in sorted(RTL.glob("*.v")))
    ys.write_text(f"""
read_verilog -sv {sources}
chparam -set BIT_WIDTH {bw} -set ENTRY_BITS {eb} -set NUM_ARRAYS {na} -set DATA_WIDTH {data_width} -set CAM_IMPL {cam_impl} top_spatial_memory
hierarchy -top top_spatial_memory
synth_xilinx -flatten -top top_spatial_memory -family xc7
tee -o {str(OUT / (cfg + '.stat')).replace(chr(92), '/')} stat
# LUT 段数を測る。Xilinx の FF プリミティブ（FD*）は ltp -noff が除外しないので、
# FF セルと BRAM（同期読み出しなので経路の端点）を消し、レジスタ / RAM ポート間の
# 組み合わせ経路だけを残す（stat の後なので資源量には影響しない）
delete t:FD* t:BUFG t:RAMB*
tee -a {str(OUT / (cfg + '.stat')).replace(chr(92), '/')} ltp
""", encoding="utf-8")
    r = subprocess.run([yosys, "-q", "-l", str(log), "-s", str(ys)], capture_output=True, text=True)
    if r.returncode != 0:
        print(r.stdout[-2000:], r.stderr[-2000:])
        print(f"[{cfg}] SYNTH ERROR (see {log})")
        return None
    stat = (OUT / f"{cfg}.stat").read_text(encoding="utf-8", errors="replace")
    return summarize(cfg, bw, ne, na, data_width, stat)


def summarize(cfg, bw, ne, na, dw, stat):
    cells = {}
    for m in re.finditer(r"^\s*(\d+)\s+([A-Za-z_$][\w$]*)\s*$", stat, re.M):
        cells[m.group(2)] = cells.get(m.group(2), 0) + int(m.group(1))
    luts = sum(v for k, v in cells.items() if re.fullmatch(r"LUT[1-6]", k))
    ffs = sum(v for k, v in cells.items() if k.startswith("FD"))
    bram = sum(v for k, v in cells.items() if k.startswith("RAMB"))
    dram = sum(v for k, v in cells.items() if k.startswith("RAM") and not k.startswith("RAMB"))
    carry = cells.get("CARRY4", 0)
    muxf = sum(v for k, v in cells.items() if k.startswith("MUXF"))
    ltp = re.search(r"Longest topological path in top_spatial_memory \(length=(\d+)\)", stat)
    depth = int(ltp.group(1)) if ltp else None
    cam_bits = bw * ne * na
    return {
        "config": cfg, "bw": bw, "ne": ne, "na": na, "dw": dw, "cam_bits": cam_bits,
        "LUT": luts, "FF": ffs, "BRAM": bram, "DRAM": dram, "CARRY4": carry, "MUXF": muxf, "depth": depth,
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--config", action="append", help="BITxENTRIESxARRAYS (repeatable)")
    ap.add_argument("--data", type=int, default=64, help="DATA_WIDTH")
    ap.add_argument("--impl", choices=["ff", "bram"], default="ff", help="CAM_IMPL (ff: CAM セル版 / bram: BRAM 版)")
    args = ap.parse_args()
    yosys = find_yosys()
    rows = []
    for cfg in args.config or DEFAULT_CONFIGS:
        print(f"[{cfg}] synthesizing ...", flush=True)
        r = synth(cfg, args.data, yosys, args.impl)
        if r:
            rows.append(r)
    if not rows:
        return 1
    print()
    print(f"{'config':>16} {'CAM bits':>9} {'LUT':>7} {'FF':>7} {'BRAM':>5} {'DRAM':>5} {'CARRY4':>6} {'MUXF':>5} {'LUT depth':>9} {'LUT/bit':>8}")
    for r in rows:
        per = r["LUT"] / r["cam_bits"] if r["cam_bits"] else 0
        print(f"{r['config']:>16} {r['cam_bits']:>9} {r['LUT']:>7} {r['FF']:>7} {r['BRAM']:>5} {r['DRAM']:>5} "
              f"{r['CARRY4']:>6} {r['MUXF']:>5} {str(r['depth']):>9} {per:>8.2f}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
