#!/usr/bin/env bash
# Rebuild the rv32ui hex images from the official riscv-tests sources.
#
#   ./build.sh /path/to/riscv-tests      (git clone https://github.com/riscv-software-src/riscv-tests)
#
# Needs riscv64-unknown-elf-gcc (or set CROSS=riscv32-unknown-elf-) and python3.
# The prebuilt images in hex/ are checked in, so this is only needed to regenerate them.
set -euo pipefail

SRC=${1:?usage: build.sh /path/to/riscv-tests}
CROSS=${CROSS:-riscv64-unknown-elf-}
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=$HERE/hex
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$OUT"

# Skipped: fence_i (needs Zifencei / self-modifying code),
#          ma_data (misaligned accesses, which this core does not trap or emulate).
SKIP="fence_i ma_data"

for s in "$SRC"/isa/rv32ui/*.S; do
  t=$(basename "$s" .S)
  case " $SKIP " in *" $t "*) continue ;; esac

  "${CROSS}gcc" -march=rv32i -mabi=ilp32 -static -nostdlib -nostartfiles \
      -I"$HERE/env" -I"$SRC/isa/macros/scalar" -T"$HERE/link.ld" \
      -o "$TMP/$t.elf" "$s"
  "${CROSS}objcopy" -O binary -j .text "$TMP/$t.elf" "$TMP/$t.text.bin"
  "${CROSS}objcopy" -O binary -j .data "$TMP/$t.elf" "$TMP/$t.data.bin"
  python3 "$HERE/bin2hex.py" "$TMP/$t.text.bin" "$OUT/$t.text.hex"
  python3 "$HERE/bin2hex.py" "$TMP/$t.data.bin" "$OUT/$t.data.hex"
  echo "built $t"
done
