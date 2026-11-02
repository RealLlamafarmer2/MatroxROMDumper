# MGAROM – Matrox video BIOS ROM dumper for DOS

A small DOS `.COM` tool (~4 KB) that reads the video BIOS ROM of a Matrox PCI/AGP
graphics card and saves it to a file. It also prints a short diagnostic report.

It was written to help recover a Matrox Mystique 220 after a bad BIOS/PINS flash.
In that situation `PROGBIOS` can write the ROM but can't read it back, and the card
can't POST, so you can't read the BIOS from the usual `C000` address. MGAROM reads
the ROM chip on the card directly, so it works while **another card is the primary
display**.

## Features

- Finds the card through PCI configuration space (mechanism #1). No drivers needed.
- Reports: bus/device, vendor and device ID, chip name, revision, BARs, the ROM BAR,
  and the Matrox `OPTION` register, including the **`biosen`** (BIOS ROM enable) and
  `vgaioen` bits.
- Warns when `biosen = 0`. That means the card's ROM is turned off by a hardware
  strap or jumper, so the system BIOS will never run it.
- Dumps the ROM to `MGAROM.BIN` (up to 64 KB) and checks:
  - the `55 AA` signature
  - the size byte and the 8-bit checksum
  - whether the image is all `FF` (blank or erased)
- Writes everything shown on screen to `MGAROM.TXT` as well.
- Puts all PCI registers it changed back to their original values before it exits.

## Usage

```
MGAROM            dump device 051A (Mystique); falls back to the first Matrox card found
MGAROM 0521       dump the first Matrox card with PCI device ID 0521 (G200 AGP)
MGAROM *          dump the first Matrox card of any type
MGAROM ?          show help
```

**For best results, boot DOS without EMM386/JEMM/QEMM.** In FreeDOS, pick the
"no drivers" boot menu entry or press F5 at boot. Some reads need the CPU in real
mode, and memory managers can also occupy the `D000` area that MGAROM uses.

### Example output

```
MGAROM 1.1 - Matrox video BIOS ROM dumper

Card at bus 00 device 0B
Vendor:Device: 102B:051A  MGA-1064SG/1164SG Mystique
Revision: 03  (MGA-1164SG = Mystique 220)
Status/Command (04h): 02800003
BAR 10h: E6000000
BAR 14h: E4000000
BAR 18h: E5000000
ROM BAR (30h): 00000000
OPTION (40h): 40000100  biosen(b30)=1  vgaioen(b8)=1
ROM BAR size: 00010000

Method A: ROM mapped at 000D0000
Saved MGAROM.BIN, bytes: 00010000
First bytes: 55 AA 40  -> 55 AA signature OK
Checksum over 00008000 bytes: 00  -> OK

PCI registers restored. Output: MGAROM.BIN, MGAROM.TXT
```

(These values are only an illustration. Your addresses will differ.)

## How it works

1. Scans PCI buses 0–7 for the vendor/device ID you asked for.
2. Measures the expansion ROM BAR (config offset `30h`) to find the ROM size.
3. Turns on `OPTION.biosen` (bit 30 of config register `40h`) and memory decoding,
   so the Matrox chip responds to ROM reads.
4. **Method A:** finds an unused, all-`FF` window below 1 MB (`D0000`, `D8000`,
   `C8000`, `E0000`), points the ROM BAR at it, and copies the ROM out with normal
   real-mode memory reads. This also works under EMM386, as long as the window is free.
5. **Method B:** used if Method A finds no free window or reads only `FF`, and the CPU
   is in real mode. It switches to *unreal mode* (a 4 GB `FS` limit) and reads the ROM
   at the high address the BIOS assigned. It turns on A20 with the "fast A20" port
   `92h`.
6. Restores the original ROM BAR, `OPTION` and Command registers.

The tool only **reads** the ROM. It never writes to the flash chip.

## Reading the result

| Report | Meaning |
|---|---|
| `55 AA` OK, checksum OK | The ROM image is valid. Compare it with your reference file, skipping the PINS block. |
| Bad signature / bad checksum | The BIOS code on the chip is corrupt. Reflash it. |
| `all FF` | The chip is blank or erased, or the ROM couldn't be reached. Retry with a clean boot. |
| `biosen=0` | The card's ROM is turned off by a strap or jumper. The card can't POST as primary until that's fixed. |

### Matrox PINS note

Matrox cards keep their board-specific settings (memory and pixel clocks, RAMDAC
limits and so on) in a **PINS** block inside the same ROM. The 16-bit pointer at ROM
offset `7FFCh` points to it. On the Mystique it's a 64-byte block starting with `.A`
(`2E 41 40`), and its bytes sum to `00`. BIOS images downloaded from Matrox usually
come with a blank PINS template, so expect the PINS bytes to differ when you compare
a dump with a stock BIOS file.

## Adapting it to other cards

Everything you're likely to change is near the top of `src/mgarom.s`:

```asm
.equ TARGET_VENDOR,  0x102B      # PCI vendor ID (Matrox)
.equ DEFAULT_DEVICE, 0x051A      # device used when no argument is given
.equ MAX_BUS,        8           # PCI buses to scan
.equ MAX_DUMP,       0x10000     # max bytes to dump
.equ OPT_REG,        0x40        # vendor "ROM enable" register
.equ OPT_BIOSEN,     0x40000000  # bit to set in OPT_REG to enable the ROM
```

- **Another Matrox card:** run it with the device ID (`MGAROM 0525`), or change
  `DEFAULT_DEVICE`. To have the report show your card's name, add it to `devtab`.
- **Bigger ROMs:** raise `MAX_DUMP`. Method A only works with ROMs of 64 KB or less,
  because of the windows below 1 MB. Bigger ROMs go through Method B.
- **Other vendors:** change `TARGET_VENDOR`. If the chip has no vendor-specific
  "ROM enable" bit, set `OPT_BIOSEN` to `0`. The `OPTION` lines in the report won't
  mean anything for that vendor.
- **Different memory holes:** edit the `cands` list.

## Building

You need GNU binutils (`as` and `ld`). They work on Linux, in WSL on Windows, or in
MSYS2.

```sh
make            # builds bin/MGAROM.COM
make clean
```

or by hand:

```sh
as --32 src/mgarom.s -o mgarom.o
ld -m elf_i386 -Ttext 0x100 -e _start --oformat binary mgarom.o -o bin/MGAROM.COM
```

`build.sh` and `build.bat` (WSL) do the same thing. A prebuilt `bin/MGAROM.COM` is
included.

## Requirements and limits

- A 386 or newer CPU, and a PCI chipset that uses configuration mechanism #1
  (virtually every 486 PCI and later board).
- MS-DOS, FreeDOS, or a Windows 9x DOS-mode boot. It won't work in a Windows DOS box.
- Only function 0 of each PCI device is scanned.
- **Disclaimer:** use at your own risk. The tool only reads, but it changes PCI
  configuration registers while it runs. If it hangs, power-cycle the PC.

## License

MIT. See [LICENSE](LICENSE).
