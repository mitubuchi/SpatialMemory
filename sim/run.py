#!/usr/bin/env python3
"""RTL を Icarus Verilog でコンパイルして、tb/ の各テストベンチを実行する。

    python sim/run.py            # 全部
    python sim/run.py basic      # tb_basic だけ

iverilog は PATH か、OSS CAD Suite をユーザー領域に展開した場所から探す。
各テストベンチは最後に "ALL TESTS PASSED" を出す。出なければ失敗。
"""
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RTL = ROOT / "rtl"
TB = ROOT / "tb"
OUT = ROOT / "sim" / "out"

CANDIDATE_BINS = [
    Path(os.environ.get("LOCALAPPDATA", "")) / "Programs" / "oss-cad-suite" / "bin",
    Path(os.environ.get("OSS_CAD_SUITE", "")) / "bin",
]


def find_tool(name):
    for d in CANDIDATE_BINS:
        for ext in (".exe", ""):
            p = d / (name + ext)
            if p.is_file():
                # OSS CAD Suite の exe は同梱の lib/ の DLL を要る。PATH に通しておく
                root = d.parent
                os.environ["PATH"] = os.pathsep.join(
                    [str(root / "bin"), str(root / "lib"), os.environ.get("PATH", "")])
                return str(p)
    return name  # PATH に任せる


def run_tb(tb_file, iverilog, vvp):
    OUT.mkdir(parents=True, exist_ok=True)
    vvp_file = OUT / (tb_file.stem + ".vvp")
    sources = sorted(RTL.glob("*.v")) + [tb_file]
    cmd = [iverilog, "-g2005", "-Wall", "-o", str(vvp_file)] + [str(s) for s in sources]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        print(r.stdout, r.stderr)
        print(f"[{tb_file.stem}] COMPILE ERROR")
        return False
    if r.stderr.strip():
        print(r.stderr.strip())
    r = subprocess.run([vvp, "-n", str(vvp_file)], capture_output=True, text=True)
    print(r.stdout.strip())
    ok = "ALL TESTS PASSED" in r.stdout
    print(f"[{tb_file.stem}] {'OK' if ok else 'FAILED'}")
    return ok


def main():
    iverilog, vvp = find_tool("iverilog"), find_tool("vvp")
    wanted = sys.argv[1:]
    tbs = sorted(TB.glob("tb_*.v"))
    if wanted:
        tbs = [t for t in tbs if any(w in t.stem for w in wanted)]
    if not tbs:
        print("no testbench matched", file=sys.stderr)
        return 2
    results = [run_tb(t, iverilog, vvp) for t in tbs]
    print(f"{sum(results)}/{len(results)} testbenches passed")
    return 0 if all(results) else 1


if __name__ == "__main__":
    sys.exit(main())
