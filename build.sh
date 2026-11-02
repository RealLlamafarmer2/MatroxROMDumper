#!/bin/sh
# Build MGAROM.COM with GNU binutils (Linux / WSL / MSYS2)
set -e
cd "$(dirname "$0")"
mkdir -p build bin
as --32 src/mgarom.s -o build/mgarom.o
ld -m elf_i386 -Ttext 0x100 -e _start --oformat binary build/mgarom.o -o bin/MGAROM.COM
echo "Built bin/MGAROM.COM ($(wc -c < bin/MGAROM.COM) bytes)"
