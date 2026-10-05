#!/usr/bin/env python3
"""Convert a raw little-endian binary into a $readmemh image of 32-bit words."""
import sys

src, dst = sys.argv[1], sys.argv[2]
data = open(src, "rb").read()
data += b"\x00" * (-len(data) % 4)
if not data:
    data = b"\x00" * 4      # keep $readmemh happy when a section is empty
with open(dst, "w") as f:
    for i in range(0, len(data), 4):
        f.write("%08x\n" % int.from_bytes(data[i:i + 4], "little"))
