#!/usr/bin/env python3
"""Convert a little-endian flat binary into one 32-bit word per readmemh line."""
import pathlib
import sys

source, destination = map(pathlib.Path, sys.argv[1:3])
data = source.read_bytes()
if len(data) > 65536:
    raise SystemExit("program image exceeds 64 KiB SRAM")
data += bytes((-len(data)) % 4)
with destination.open("w", encoding="ascii") as output:
    for offset in range(0, len(data), 4):
        output.write(f"{int.from_bytes(data[offset:offset + 4], 'little'):08x}\n")
