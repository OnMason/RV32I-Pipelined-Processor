# Official rv32ui tests

`hex/` holds prebuilt images of the `rv32ui` tests from
[riscv-software-src/riscv-tests](https://github.com/riscv-software-src/riscv-tests),
assembled for this core's memory layout (code at `0x0000` in the instruction ROM,
data at `0x2000` in the data RAM). Each test has a `.text.hex` and a `.data.hex`
image in `$readmemh` format, one 32-bit word per line.

Run them with `make riscv-tests` from the repository root.

- `env/riscv_test.h` — minimal environment: a test ends in a jump-to-self with
  `x26 = 0x600D` on pass, or `x26 = 0xBAD` and the failing case number in `x27`.
- `link.ld` — linker script for the Harvard layout.
- `build.sh` — regenerates `hex/` from a riscv-tests checkout (needs a RISC-V GCC).

Not included: `fence_i` (Zifencei, self-modifying code) and `ma_data`
(misaligned accesses, which this core does not trap).

## License of the test sources

The images in `hex/` are built from riscv-tests, which is distributed under the
following license:

```
Copyright (c) 2012-2015, The Regents of the University of California (Regents).
All Rights Reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:
1. Redistributions of source code must retain the above copyright
   notice, this list of conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright
   notice, this list of conditions and the following disclaimer in the
   documentation and/or other materials provided with the distribution.
3. Neither the name of the Regents nor the
   names of its contributors may be used to endorse or promote products
   derived from this software without specific prior written permission.

IN NO EVENT SHALL REGENTS BE LIABLE TO ANY PARTY FOR DIRECT, INDIRECT,
SPECIAL, INCIDENTAL, OR CONSEQUENTIAL DAMAGES, INCLUDING LOST PROFITS, ARISING
OUT OF THE USE OF THIS SOFTWARE AND ITS DOCUMENTATION, EVEN IF REGENTS HAS
BEEN ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

REGENTS SPECIFICALLY DISCLAIMS ANY WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
PURPOSE. THE SOFTWARE AND ACCOMPANYING DOCUMENTATION, IF ANY, PROVIDED
HEREUNDER IS PROVIDED "AS IS". REGENTS HAS NO OBLIGATION TO PROVIDE
MAINTENANCE, SUPPORT, UPDATES, ENHANCEMENTS, OR MODIFICATIONS.
```
