/* Harvard layout: code is loaded into the instruction ROM at 0x0000,
   data into the data RAM at 0x2000. */
OUTPUT_ARCH("riscv")
ENTRY(_start)

SECTIONS
{
  . = 0x00000000;
  .text : { *(.text.init) *(.text*) }

  . = 0x00002000;
  .data : { *(.data*) *(.sdata*) *(.rodata*) *(.bss*) *(.sbss*) }

  /DISCARD/ : { *(.riscv.attributes) *(.comment) *(.note*) *(.eh_frame*) }
}
