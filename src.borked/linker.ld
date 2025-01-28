/* Based on the linker script from libdragon's IPL3 bootloader
   (boot/ipl3_dev.ld), which produces a ROM in the right structure
   (that simply needs extracted from the resulting ELF). */

OUTPUT_FORMAT ("elf32-bigmips", "elf32-bigmips", "elf32-littlemips")
OUTPUT_ARCH (mips)
ENTRY (_start)

MEMORY {
    rom  : ORIGIN = 0xB0000000, LENGTH = 8M
    dmem : ORIGIN = 0xA4000000, LENGTH = 4096
}

SECTIONS {
    /DISCARD/ : { *(.MIPS.abiflags) }

    .text.prologue 0xB0000000 : {
        KEEP(*(.header))
        KEEP(*(.text.ipl3_trampoline))
        KEEP(*(.text.ique_trampoline))
    } > rom

    .text.dmem 0xA4000040 : AT ( 0xB0001040 ) {
        LONG(0x3044d236); /* dummy value that's probably unneeded */
        KEEP(*(.stage1.pre))
        KEEP(*(.stage1))
        . = ALIGN(16);
        *(.text.boot)
        *(.rodata.boot)
        *(.bss.boot)
        *(.data.boot)
        . = ALIGN(8);
    } > dmem

    .text.rom 0xB0001040 + SIZEOF ( .text.dmem ) : {
        . = ALIGN(8);
        *(.text)
        *(.text.*)
        *(.rodata)
        *(.rodata.*)
        /* This is probably technically wrong, but it shouldn't matter
           because _start is gonna handle setting up the stack and
           heap anyway. */
        *(.bss)
        *(.bss.*)
        *(.data)
        *(.data.*)
    } > rom
}
