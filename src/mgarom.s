# =====================================================================
#  MGAROM - Matrox PCI/AGP video BIOS ROM dumper for DOS
#
#  Reads the option ROM (flash/EEPROM) of a Matrox graphics card and
#  saves it to MGAROM.BIN, with a diagnostic report in MGAROM.TXT.
#  Works on a SECONDARY card (another card can be the primary display).
#
#  Build (GNU binutils, Linux / WSL / MSYS2):
#     as --32 src/mgarom.s -o mgarom.o
#     ld -m elf_i386 -Ttext 0x100 -e _start --oformat binary mgarom.o -o MGAROM.COM
#  or simply:  make
#
#  Usage:  MGAROM            dump first Mystique (102B:051A), else first Matrox card
#          MGAROM 0521       dump first Matrox card with device ID 0521 (G200 AGP)
#          MGAROM *          dump first Matrox card of any device ID
#          MGAROM ?          help
#
#  Requires a 386+ CPU and PCI configuration mechanism #1.
#  SPDX-License-Identifier: MIT
# =====================================================================

        .intel_syntax noprefix
        .code16

# ---------------------------------------------------------------------
#  Tunables - change these to adapt the tool to another card/vendor
# ---------------------------------------------------------------------
        .equ TARGET_VENDOR,  0x102B      # Matrox
        .equ DEFAULT_DEVICE, 0x051A      # MGA-1064SG/1164SG Mystique / Mystique 220
        .equ MAX_BUS,        8           # scan PCI buses 0..MAX_BUS-1
        .equ MAX_DUMP,       0x10000     # cap on bytes dumped (64 KB)
        .equ OPT_REG,        0x40        # Matrox OPTION register (PCI config)
        .equ OPT_BIOSEN,     0x40000000  # OPTION bit 30: BIOS ROM enable
        .equ OPT_VGAIOEN,    0x00000100  # OPTION bit 8 : VGA I/O enable
        .equ CHUNK,          4096        # file write chunk size

        .text
        .globl _start
_start:
        cld
        mov word ptr [target], DEFAULT_DEVICE
        call parse_args

        # --- open report file
        mov ah, 0x3C
        xor cx, cx
        mov dx, offset fn_txt
        int 0x21
        jc 1f
        mov [rep_h], ax
1:
        mov si, offset s_banner
        call puts

        smsw ax
        and al, 1
        mov [v86], al
        jz 2f
        mov si, offset s_v86
        call puts
2:
        # --- PCI config mechanism #1 present?
        mov dx, 0xCF8
        mov eax, 0x80000000
        out dx, eax
        in eax, dx
        cmp eax, 0x80000000
        je pci_ok
        mov si, offset s_nopci
        call puts
        jmp exit

# ---------------------------------------------------------------------
#  Scan for the card (function 0 of every device on buses 0..MAX_BUS-1)
# ---------------------------------------------------------------------
pci_ok:
        mov dword ptr [bdf], 0x80000000
scan:
        xor al, al
        call pci_read
        cmp ax, TARGET_VENDOR
        jne scan_skip
        shr eax, 16
        cmp byte ptr [anydev], 0
        jne found
        cmp ax, [target]
        je found
        cmp dword ptr [alt_bdf], 0
        jne scan_skip
        mov eax, [bdf]
        mov [alt_bdf], eax
scan_skip:
        add dword ptr [bdf], 0x800          # next device number
        cmp dword ptr [bdf], 0x80000000 + (MAX_BUS << 16)
        jb scan
        mov eax, [alt_bdf]
        test eax, eax
        jnz use_alt
        mov si, offset s_notfound
        call puts
        jmp exit
use_alt:
        mov [bdf], eax
        mov si, offset s_alt
        call puts

# ---------------------------------------------------------------------
#  Report PCI configuration
# ---------------------------------------------------------------------
found:
        mov si, offset s_loc
        call puts
        mov eax, [bdf]
        shr eax, 16
        call phex8
        mov si, offset s_dev
        call puts
        mov eax, [bdf]
        shr eax, 11
        and al, 0x1F
        call phex8
        call crlf

        mov si, offset s_id
        call puts
        xor al, al
        call pci_read
        mov [devid], eax
        push eax
        call phex16
        mov si, offset s_colon
        call puts
        pop eax
        shr eax, 16
        call phex16
        mov si, offset s_sp2
        call puts
        call print_devname
        call crlf

        mov si, offset s_rev
        call puts
        mov al, 0x08
        call pci_read
        mov [rev], al
        call phex8
        # special case: Mystique rev 03 is the Mystique 220 (MGA-1164SG)
        cmp word ptr [devid+2], 0x051A
        jne 3f
        cmp byte ptr [rev], 3
        jb 3f
        mov si, offset s_rev220
        call puts
3:      call crlf

        mov si, offset s_cmd
        call puts
        mov al, 0x04
        call pci_read
        mov [orig_cmd], eax
        call phex32
        call crlf

        mov bl, 0x10                        # BARs 10h, 14h, 18h
4:      mov si, offset s_bar
        call puts
        mov al, bl
        call phex8
        mov si, offset s_eq
        call puts
        mov al, bl
        call pci_read
        call phex32
        call crlf
        add bl, 4
        cmp bl, 0x1C
        jb 4b

        mov si, offset s_rombar
        call puts
        mov al, 0x30
        call pci_read
        mov [orig_rom], eax
        call phex32
        call crlf

        mov si, offset s_opt
        call puts
        mov al, OPT_REG
        call pci_read
        mov [orig_opt], eax
        call phex32
        mov si, offset s_biosen
        call puts
        mov eax, [orig_opt]
        shr eax, 30
        and al, 1
        call pdigit
        mov si, offset s_vgaioen
        call puts
        mov eax, [orig_opt]
        shr eax, 8
        and al, 1
        call pdigit
        call crlf
        test dword ptr [orig_opt], OPT_BIOSEN
        jnz 5f
        mov si, offset s_biosoff
        call puts
5:
# ---------------------------------------------------------------------
#  Size the expansion ROM BAR
# ---------------------------------------------------------------------
        mov cl, 0x30
        mov eax, 0xFFFFF800
        call pci_write
        mov al, 0x30
        call pci_read
        and eax, 0xFFFFF800
        push eax
        mov cl, 0x30
        mov eax, [orig_rom]
        call pci_write
        pop eax
        test eax, eax
        jnz 6f
        mov si, offset s_norom
        call puts
        jmp restore
6:      neg eax
        mov [romsize], eax
        mov si, offset s_romsz
        call puts
        call phex32
        call crlf
        mov eax, [romsize]
        cmp eax, MAX_DUMP
        jbe 7f
        mov eax, MAX_DUMP
7:      mov [dumpsize], eax

        # enable ROM decode on the chip and memory space decode
        mov eax, [orig_opt]
        or eax, OPT_BIOSEN
        mov cl, OPT_REG
        call pci_write
        mov eax, [orig_cmd]
        or al, 2
        mov cl, 0x04
        call pci_write

# ---------------------------------------------------------------------
#  Method A: map the ROM into an unused hole below 1 MB (C800-EFFF)
# ---------------------------------------------------------------------
        mov word ptr [candp], offset cands
candloop:
        mov si, [candp]
        mov eax, [si]
        add word ptr [candp], 4
        test eax, eax
        jz methodA_done
        mov ebx, [dumpsize]
        dec ebx
        test eax, ebx                       # must be aligned to ROM size
        jnz candloop
        mov [maddr], eax
        shr eax, 4                          # hole must read all FF first
        mov fs, ax
        xor esi, esi
        mov ecx, [dumpsize]
        shr ecx, 2
8:      cmp dword ptr fs:[esi], 0xFFFFFFFF
        jne candloop
        add esi, 4
        dec ecx
        jnz 8b
        mov eax, [maddr]                    # map ROM there
        or al, 1
        mov cl, 0x30
        call pci_write
        cmp byte ptr [v86], 0
        jne 9f
        wbinvd
9:      mov si, offset s_tryA
        call puts
        mov eax, [maddr]
        call phex32
        call crlf
        mov eax, [maddr]
        shr eax, 4
        mov fs, ax
        xor esi, esi
        call dump_rom
        mov byte ptr [didA], 1
        mov cl, 0x30
        mov eax, [orig_rom]
        call pci_write

methodA_done:
        cmp byte ptr [didA], 0
        jne 10f
        mov si, offset s_noholes
        call puts
        jmp tryB
10:     cmp byte ptr [allff], 0
        je restore                          # got real data -> done

# ---------------------------------------------------------------------
#  Method B: read the ROM at its BIOS-assigned address above 1 MB
#            using "unreal" (flat real) mode. Needs real mode (no EMM386).
# ---------------------------------------------------------------------
tryB:
        cmp byte ptr [v86], 0
        je 11f
        mov si, offset s_noB_v86
        call puts
        jmp restore
11:     mov eax, [orig_rom]
        and eax, 0xFFFFF800
        cmp eax, 0x100000
        jae 12f
        mov si, offset s_noB_addr
        call puts
        jmp restore
12:     mov [maddr], eax
        mov si, offset s_tryB
        call puts
        mov eax, [maddr]
        call phex32
        call crlf
        call a20_on
        call enter_unreal
        mov eax, [maddr]
        or al, 1
        mov cl, 0x30
        call pci_write
        wbinvd
        xor ax, ax
        mov fs, ax
        mov esi, [maddr]
        call dump_rom
        mov cl, 0x30
        mov eax, [orig_rom]
        call pci_write

# ---------------------------------------------------------------------
restore:
        mov cl, 0x30
        mov eax, [orig_rom]
        call pci_write
        mov cl, OPT_REG
        mov eax, [orig_opt]
        call pci_write
        mov cl, 0x04
        mov eax, [orig_cmd]
        call pci_write
        mov si, offset s_done
        call puts
exit:
        mov bx, [rep_h]
        test bx, bx
        jz 13f
        mov ah, 0x3E
        int 0x21
13:     mov ax, 0x4C00
        int 0x21

# =====================================================================
#  parse_args: [target] / [anydev] from the command tail (PSP:80h)
# =====================================================================
parse_args:
        mov si, 0x81
        movzx cx, byte ptr [0x80]
        add cx, si                          # cx = end of tail
1:      cmp si, cx
        jae pa_ret
        mov al, [si]
        cmp al, ' '
        je 2f
        cmp al, 9
        jne 3f
2:      inc si
        jmp 1b
3:      cmp al, '?'
        je pa_help
        cmp al, '/'
        je pa_help
        cmp al, '*'
        jne 4f
        mov byte ptr [anydev], 1
        ret
4:      xor dx, dx                          # parse up to 4 hex digits
        xor bx, bx                          # bx = digit count
5:      cmp si, cx
        jae 7f
        mov al, [si]
        call hexval
        jc 7f
        shl dx, 4
        or dl, al
        inc si
        inc bx
        cmp bx, 4
        jb 5b
7:      test bx, bx
        jz pa_help
        mov [target], dx
pa_ret: ret
pa_help:
        mov si, offset s_help
        call puts
        mov ax, 0x4C01
        int 0x21

hexval:                                     # al = char -> al = 0..15, CF=1 if invalid
        cmp al, '0'
        jb 9f
        cmp al, '9'
        jbe 1f
        and al, 0xDF                        # upper-case
        cmp al, 'A'
        jb 9f
        cmp al, 'F'
        ja 9f
        sub al, 'A' - 10
        clc
        ret
1:      sub al, '0'
        clc
        ret
9:      stc
        ret

# =====================================================================
#  print_devname: look up [devid+2] in devtab and print its name
# =====================================================================
print_devname:
        push ax
        push bx
        push si
        mov ax, [devid+2]
        mov bx, offset devtab
1:      cmp word ptr [bx+2], 0
        je 3f
        cmp ax, [bx]
        je 2f
        add bx, 4
        jmp 1b
2:      mov si, [bx+2]
        call puts
        jmp 4f
3:      mov si, offset s_unknown
        call puts
4:      pop si
        pop bx
        pop ax
        ret

# =====================================================================
#  dump_rom: copy [dumpsize] bytes from fs:esi to MGAROM.BIN, analyse
# =====================================================================
dump_rom:
        mov byte ptr [allff], 1
        mov ah, 0x3C
        xor cx, cx
        mov dx, offset fn_bin
        push fs
        push esi
        int 0x21
        pop esi
        pop fs
        jnc 1f
        mov si, offset s_ferr
        call puts
        ret
1:      mov [bin_h], ax
        mov dword ptr [done], 0
        mov byte ptr [csum], 0
dr_chunk:
        mov ecx, [dumpsize]
        sub ecx, [done]
        jz dr_fin
        cmp ecx, CHUNK
        jbe 2f
        mov ecx, CHUNK
2:      mov [clen], cx
        mov di, offset chunkbuf
        shr cx, 2
3:      mov eax, dword ptr fs:[esi]         # 32-bit reads from the ROM
        mov [di], eax
        add esi, 4
        add di, 4
        dec cx
        jnz 3b
        cmp dword ptr [done], 0
        jne 5f
        movzx eax, byte ptr [chunkbuf+2]    # ROM size byte (x 512)
        shl eax, 9
        jnz 4f
        mov eax, [dumpsize]
4:      mov [cklimit], eax
        mov ax, [chunkbuf]
        mov [sig], ax
        mov al, [chunkbuf+2]
        mov [szb], al
5:      mov bx, offset chunkbuf
        mov edx, [done]
        mov cx, [clen]
6:      mov al, [bx]
        cmp al, 0xFF
        je 7f
        mov byte ptr [allff], 0
7:      cmp edx, [cklimit]
        jae 8f
        add [csum], al
8:      inc bx
        inc edx
        dec cx
        jnz 6b
        push fs                             # DOS may not keep fs / high esi
        push esi
        mov ah, 0x40
        mov bx, [bin_h]
        mov cx, [clen]
        mov dx, offset chunkbuf
        int 0x21
        pop esi
        pop fs
        movzx eax, word ptr [clen]
        add [done], eax
        jmp dr_chunk
dr_fin:
        mov ah, 0x3E
        mov bx, [bin_h]
        int 0x21
        mov si, offset s_saved
        call puts
        mov eax, [done]
        call phex32
        call crlf
        mov si, offset s_first
        call puts
        mov ax, [sig]
        call phex8
        mov si, offset s_sp
        call puts
        mov al, byte ptr [sig+1]
        call phex8
        mov si, offset s_sp
        call puts
        mov al, [szb]
        call phex8
        mov si, offset s_sigok
        cmp word ptr [sig], 0xAA55
        je 9f
        mov si, offset s_sigbad
9:      call puts
        mov si, offset s_ck1
        call puts
        mov eax, [cklimit]
        call phex32
        mov si, offset s_ck2
        call puts
        mov al, [csum]
        call phex8
        mov si, offset s_ckok
        cmp byte ptr [csum], 0
        je 10f
        mov si, offset s_ckbad
10:     call puts
        cmp byte ptr [allff], 0
        je 11f
        mov si, offset s_allff
        call puts
11:     ret

# =====================================================================
#  PCI config access (mechanism #1)
# =====================================================================
pci_read:                                   # al = reg -> eax
        push edx
        push ecx
        movzx ecx, al
        and cl, 0xFC
        or ecx, [bdf]
        mov eax, ecx
        mov dx, 0xCF8
        out dx, eax
        mov dx, 0xCFC
        in eax, dx
        pop ecx
        pop edx
        ret

pci_write:                                  # cl = reg, eax = value
        push edx
        push ebx
        mov ebx, eax
        movzx eax, cl
        and al, 0xFC
        or eax, [bdf]
        mov dx, 0xCF8
        out dx, eax
        mov eax, ebx
        mov dx, 0xCFC
        out dx, eax
        pop ebx
        pop edx
        ret

# =====================================================================
#  A20 + unreal mode (fs gets a 4 GB limit)
# =====================================================================
a20_on:
        in al, 0x92                         # "fast A20"
        test al, 2
        jnz 1f
        or al, 2
        and al, 0xFE                        # never touch the reset bit
        out 0x92, al
1:      ret

enter_unreal:
        pushf
        cli
        xor eax, eax
        mov ax, ds
        shl eax, 4
        add eax, offset gdt
        mov [gdtr+2], eax
        lgdt [gdtr]
        mov eax, cr0
        or al, 1
        mov cr0, eax
        jmp 1f
1:      mov bx, 8
        mov fs, bx
        and al, 0xFE
        mov cr0, eax
        jmp 2f
2:      xor ax, ax
        mov fs, ax
        popf
        ret

# =====================================================================
#  Output helpers (screen + MGAROM.TXT)
# =====================================================================
puts:                                       # si -> zero-terminated string
        push ax
        push bx
        push cx
        push dx
        push di
        mov di, si
1:      cmp byte ptr [di], 0
        je 2f
        inc di
        jmp 1b
2:      mov cx, di
        sub cx, si
        jz 3f
        mov dx, si
        mov bx, 1
        mov ah, 0x40
        int 0x21
        mov bx, [rep_h]
        test bx, bx
        jz 3f
        mov cx, di
        sub cx, si
        mov dx, si
        mov ah, 0x40
        int 0x21
3:      pop di
        pop dx
        pop cx
        pop bx
        pop ax
        ret

crlf:
        push si
        mov si, offset s_crlf
        call puts
        pop si
        ret

pdigit:                                     # al = 0..9
        push si
        add al, '0'
        mov [hexbuf], al
        mov byte ptr [hexbuf+1], 0
        mov si, offset hexbuf
        call puts
        pop si
        ret

phex32: push cx
        mov cx, 8
        jmp phexn
phex16: push cx
        shl eax, 16
        mov cx, 4
        jmp phexn
phex8:  push cx
        shl eax, 24
        mov cx, 2
phexn:  push eax
        push bx
        push di
        push si
        mov di, offset hexbuf
1:      rol eax, 4
        mov bl, al
        and bx, 0x0F
        mov bl, [hexdig+bx]
        mov [di], bl
        inc di
        dec cx
        jnz 1b
        mov byte ptr [di], 0
        mov si, offset hexbuf
        call puts
        pop si
        pop di
        pop bx
        pop eax
        pop cx
        ret

# =====================================================================
#  Data
# =====================================================================
        .p2align 2
gdt:    .long 0, 0
        .word 0xFFFF, 0                     # flat 4 GB data segment
        .byte 0, 0x92, 0xCF, 0
gdtr:   .word 15
        .long 0

# Method A candidate windows below 1 MB (tried in order, 0 = end)
cands:  .long 0x0D0000, 0x0D8000, 0x0C8000, 0x0E0000, 0

# Known Matrox device IDs (from pci.ids). Add your card here.
devtab: .word 0x0518, n_0518
        .word 0x0519, n_0519
        .word 0x051A, n_051A
        .word 0x051B, n_051B
        .word 0x051E, n_051E
        .word 0x051F, n_051F
        .word 0x0520, n_0520
        .word 0x0521, n_0521
        .word 0x0525, n_0525
        .word 0x0527, n_0527
        .word 0x0528, n_0528
        .word 0x1000, n_1000
        .word 0x1001, n_1001
        .word 0x2527, n_2527
        .word 0, 0

bdf:      .long 0
alt_bdf:  .long 0
devid:    .long 0
orig_cmd: .long 0
orig_opt: .long 0
orig_rom: .long 0
romsize:  .long 0
dumpsize: .long 0
maddr:    .long 0
done:     .long 0
cklimit:  .long 0
target:   .word 0
candp:    .word 0
rep_h:    .word 0
bin_h:    .word 0
clen:     .word 0
sig:      .word 0
szb:      .byte 0
csum:     .byte 0
allff:    .byte 0
v86:      .byte 0
didA:     .byte 0
anydev:   .byte 0
rev:      .byte 0
hexdig:   .ascii "0123456789ABCDEF"
hexbuf:   .space 10

n_0518: .asciz "MGA-II (Athena)"
n_0519: .asciz "MGA-2064W Millennium"
n_051A: .asciz "MGA-1064SG/1164SG Mystique"
n_051B: .asciz "MGA-2164W Millennium II"
n_051E: .asciz "MGA-1064SG Mystique AGP"
n_051F: .asciz "MGA-2164W Millennium II AGP"
n_0520: .asciz "MGA G200 PCI"
n_0521: .asciz "MGA G200 AGP"
n_0525: .asciz "MGA G400/G450"
n_0527: .asciz "Parhelia"
n_0528: .asciz "Parhelia"
n_1000: .asciz "MGA G100 PCI"
n_1001: .asciz "MGA G100 AGP"
n_2527: .asciz "Millennium G550"
s_unknown: .asciz "(unknown Matrox device)"

fn_txt:  .asciz "MGAROM.TXT"
fn_bin:  .asciz "MGAROM.BIN"
s_banner: .asciz "MGAROM 1.1 - Matrox video BIOS ROM dumper\r\n\r\n"
s_help:  .asciz "MGAROM 1.1 - Matrox video BIOS ROM dumper\r\n\r\nUsage: MGAROM [devid | *]\r\n  (none)  first device 051A (Mystique), else first Matrox card\r\n  devid   4-digit hex PCI device ID, e.g. MGAROM 0521\r\n  *       first Matrox card of any type\r\n\r\nWrites MGAROM.BIN (ROM image) and MGAROM.TXT (report).\r\nBoot without EMM386/JEMM for best results.\r\n"
s_v86:   .asciz "NOTE: CPU is in V86 mode (EMM386/JEMM loaded). Only method A available.\r\n"
s_nopci: .asciz "ERROR: PCI config mechanism #1 not found.\r\n"
s_notfound: .asciz "ERROR: No Matrox PCI/AGP card found.\r\n"
s_alt:   .asciz "WARNING: requested device ID not found, using first other Matrox device.\r\n"
s_loc:   .asciz "Card at bus "
s_dev:   .asciz " device "
s_id:    .asciz "Vendor:Device: "
s_colon: .asciz ":"
s_sp2:   .asciz "  "
s_rev:   .asciz "Revision: "
s_rev220: .asciz "  (MGA-1164SG = Mystique 220)"
s_cmd:   .asciz "Status/Command (04h): "
s_bar:   .asciz "BAR "
s_eq:    .asciz "h: "
s_rombar: .asciz "ROM BAR (30h): "
s_opt:   .asciz "OPTION (40h): "
s_biosen: .asciz "  biosen(b30)="
s_vgaioen: .asciz "  vgaioen(b8)="
s_biosoff: .asciz "*** biosen=0: the card's BIOS ROM is DISABLED (strap/jumper). System BIOS\r\n*** will never run it, so the card can't POST as primary. Check jumpers/straps.\r\n"
s_norom: .asciz "ERROR: ROM BAR not implemented/readable.\r\n"
s_romsz: .asciz "ROM BAR size: "
s_tryA:  .asciz "\r\nMethod A: ROM mapped at "
s_tryB:  .asciz "\r\nMethod B (unreal mode): ROM at "
s_noholes: .asciz "Method A: no free memory hole (C800-EFFF) - boot clean, no EMM386/UMBs.\r\n"
s_noB_v86: .asciz "Method B skipped: V86 mode. Boot without JEMM/EMM386 and retry.\r\n"
s_noB_addr: .asciz "Method B skipped: BIOS left no high ROM address assigned.\r\n"
s_ferr:  .asciz "ERROR: cannot create MGAROM.BIN\r\n"
s_saved: .asciz "Saved MGAROM.BIN, bytes: "
s_first: .asciz "First bytes: "
s_sp:    .asciz " "
s_sigok: .asciz "  -> 55 AA signature OK\r\n"
s_sigbad: .asciz "  -> BAD signature (expected 55 AA)\r\n"
s_ck1:   .asciz "Checksum over "
s_ck2:   .asciz " bytes: "
s_ckok:  .asciz "  -> OK\r\n"
s_ckbad: .asciz "  -> BAD (must be 00)\r\n"
s_allff: .asciz "WARNING: image is all FF - chip blank/erased OR ROM not reachable.\r\n"
s_done:  .asciz "\r\nPCI registers restored. Output: MGAROM.BIN, MGAROM.TXT\r\n"
s_crlf:  .asciz "\r\n"

        .p2align 2
chunkbuf:                                   # CHUNK bytes of scratch past end of image
