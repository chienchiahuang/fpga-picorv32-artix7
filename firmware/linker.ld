/* The first 2 KB (0x000-0x7FF) is reserved for firmware/bootloader/ (see
 * bootloader/boot.ld), which always runs first after reset and is baked
 * into the bitstream. Demos linked with this script start right after it,
 * so they can be reloaded over UART without re-synthesizing. */
MEMORY {
    RAM (rwx) : ORIGIN = 0x00000800, LENGTH = 14336
}

SECTIONS {
    .text : {
        *(.text.start)
        *(.text .text.*)
    } > RAM

    .rodata : {
        *(.rodata .rodata.*)
    } > RAM

    .data : {
        *(.data .data.*)
    } > RAM

    .bss (NOLOAD) : {
        _bss_start = .;
        *(.bss .bss.*)
        *(COMMON)
        . = ALIGN(4);
        _bss_end = .;
    } > RAM

    _stack_top = ORIGIN(RAM) + LENGTH(RAM);
}
