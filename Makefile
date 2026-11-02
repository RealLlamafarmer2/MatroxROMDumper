AS      ?= as
LD      ?= ld
SRC     := src/mgarom.s
OBJ     := build/mgarom.o
OUT     := bin/MGAROM.COM

all: $(OUT)

$(OBJ): $(SRC)
	@mkdir -p build
	$(AS) --32 $< -o $@

$(OUT): $(OBJ)
	@mkdir -p bin
	$(LD) -m elf_i386 -Ttext 0x100 -e _start --oformat binary $< -o $@
	@ls -l $@

disasm: $(OUT)
	objdump -D -b binary -mi8086 -M intel --adjust-vma=0x100 $(OUT)

clean:
	rm -rf build $(OUT)

.PHONY: all clean disasm
