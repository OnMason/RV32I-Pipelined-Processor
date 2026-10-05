// Minimal bare-metal environment for running the official riscv-tests rv32ui
// suite on a core with no CSRs or traps.
//
// A test ends by parking in a jump-to-self with the verdict in registers:
//   pass: x26 (s10) = 0x600D
//   fail: x26 (s10) = 0xBAD, x27 (s11) = number of the failing test case
#ifndef _ENV_RV32I_PIPELINE_H
#define _ENV_RV32I_PIPELINE_H

#define RVTEST_RV32U
#define RVTEST_RV64U

#define TESTNUM gp

#define RVTEST_CODE_BEGIN  \
        .section .text.init; \
        .globl _start;       \
_start:

#define RVTEST_CODE_END

#define RVTEST_PASS          \
        li   s10, 0x600D;    \
1:      j    1b;

#define RVTEST_FAIL          \
        mv   s11, TESTNUM;   \
        li   s10, 0xBAD;     \
1:      j    1b;

#define RVTEST_DATA_BEGIN    .section .data; .align 4;
#define RVTEST_DATA_END

#endif
