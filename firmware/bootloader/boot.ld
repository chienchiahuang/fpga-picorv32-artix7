/* The bootloader itself lives in the first 2 KB (0x000-0x7FF); everything
 * from 0x800 onward belongs to whatever demo is currently loaded there (see
 * ../linker.ld). Its stack grows down from 0x800, i.e. shares the same
 * headroom convention as a demo's own top-of-RAM stack, just capped at the
 * boundary instead of the true end of RAM -- fine, since the bootloader
 * never runs concurrently with the demo it loads. */
MEMORY {
    BOOT (rwx) : ORIGIN = 0x00000000, LENGTH = 2K
}

SECTIONS {
    .text : {
        *(.text.start)
        *(.text .text.*)
    } > BOOT

    .rodata : {
        *(.rodata .rodata.*)
    } > BOOT

    .data : {
        *(.data .data.*)
    } > BOOT

    .bss (NOLOAD) : {
        _bss_start = .;
        *(.bss .bss.*)
        *(COMMON)
        . = ALIGN(4);
        _bss_end = .;
    } > BOOT

    _stack_top = ORIGIN(BOOT) + LENGTH(BOOT);
}
