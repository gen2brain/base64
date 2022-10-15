// Copyright 2017 The Go Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

#include "textflag.h"
#include "funcdata.h"

// The SSSE3 base64 encoding code is based on the algorithms implemented
// by the C language intrinsic encoders described in the links below
//
// - Author: Wojciech Muła <wojciech_mula@poczta.onet.pl>
//   - http://0x80.pl/notesen/2016-01-12-sse-base64-encoding.html
//   - https://github.com/WojciechMula/base64simd  ( BSD 2-clause )
//
// - Authors: Alfred Klomp <git@alfredklomp.com>, Matthieu Darbois <mayeut@users.noreply.github.com>
//   - https://github.com/aklomp/base64  ( BSD 2-clause )

#define B64_LOOKUP_REG X6
#define SHUFFLE_MASK_REG X8
#define AANDC_MASK_REG X9
#define AANDC_SHIFT_REG X10
#define DANDB_MASK_REG X11
#define DANDB_SHIFT_REG X12
#define SUB51_REG X13
#define CMP26_REG X14

DATA bShuffleMask<>+0x00(SB)/8, $0x0405030401020001
DATA bShuffleMask<>+0x08(SB)/8, $0x0A0B090A07080607
DATA bAAndCMask<>+0x00(SB)/8, $0x0fc0fc000fc0fc00
DATA bAAndCMask<>+0x08(SB)/8, $0x0fc0fc000fc0fc00

DATA bAAndCShift<>+0x00(SB)/8, $0x0400004004000040
DATA bAAndCShift<>+0x08(SB)/8, $0x0400004004000040
DATA bDAndBShift<>+0x00(SB)/8, $0x0100001001000010
DATA bDAndBShift<>+0x08(SB)/8, $0x0100001001000010

DATA bDAndBMask<>+0x00(SB)/8, $0x003f03f0003f03f0
DATA bDAndBMask<>+0x08(SB)/8, $0x003f03f0003f03f0

DATA bSub51Mask<>+0x00(SB)/8, $0x3333333333333333
DATA bSub51Mask<>+0x08(SB)/8, $0x3333333333333333

DATA bCmp26Mask<>+0x00(SB)/8, $0x1919191919191919
DATA bCmp26Mask<>+0x08(SB)/8, $0x1919191919191919

GLOBL bShuffleMask<>(SB), (NOPTR+RODATA), $16
GLOBL bAAndCMask<>(SB), (NOPTR+RODATA), $16
GLOBL bAAndCShift<>(SB), (NOPTR+RODATA), $16
GLOBL bDAndBShift<>(SB), (NOPTR+RODATA), $16
GLOBL bDAndBMask<>(SB), (NOPTR+RODATA), $16
GLOBL bSub51Mask<>(SB), (NOPTR+RODATA), $16
GLOBL bCmp26Mask<>(SB), (NOPTR+RODATA), $16

// func encode12ByteGroups(lookup []int8, dst, src []byte) (di int, si int)
TEXT ·encode12ByteGroups(SB), NOSPLIT, $0-88
	NO_LOCAL_POINTERS

	XORQ SI, SI
	XORQ DI, DI

	TESTB $1, ·hasSSSE3(SB) // check for SSSE3 (PHSUFB)
	JZ    finish

	MOVQ  src_len+56(FP), BX
	MOVQ  $0x5555555555555556, AX // DX = (BX / 12) * 12
	IMULQ BX                      // Assumes DX a slice len
	SARQ  $2, DX                  // is a positive signed integer
	LEAQ  (DX)(DX*2), DX          // DX is the number of input
	SHLQ  $2, DX                  // bytes we're going to process

	MOVQ src_base+48(FP), BX  // BX points to start of 12 byte group
	MOVQ dst_base+24(FP), R14

	MOVQ  lookup_base+0(FP), R12
	MOVOU bShuffleMask<>+0(SB), SHUFFLE_MASK_REG
	MOVOU bAAndCMask<>+0(SB), AANDC_MASK_REG
	MOVOU bAAndCShift<>+0(SB), AANDC_SHIFT_REG
	MOVOU bDAndBMask<>+0(SB), DANDB_MASK_REG
	MOVOU bDAndBShift<>+0(SB), DANDB_SHIFT_REG
	MOVOU bSub51Mask<>+0(SB), SUB51_REG
	MOVOU bCmp26Mask<>+0(SB), CMP26_REG
	MOVOU (R12), B64_LOOKUP_REG

read12write16:
	MOVQ   (BX)(SI*1), X0  // Load 12 bytes
	MOVD   8(BX)(SI*1), X1
	PSLLDQ $8, X1
	POR    X1, X0          // X0 now has |----|3332|2211|1000|

	// Shuffle the bytes

	PSHUFB SHUFFLE_MASK_REG, X0

	// Each DWORD in X0 looks like
	// bbbbcccc|ccdddddd|aaaaaabb|bbbbcccc
	// where a,b,c,d correspond to the bits of the 6 bit indices

	// Extract Indices

	MOVOA X0, X1
	PAND  AANDC_MASK_REG, X0
	PAND  DANDB_MASK_REG, X1

	// X0 = 4 groups of 0000cccc|cc000000|aaaaaa00|00000000
	// X1 = 4 groups of 00000000|00dddddd|000000bb|bbbb0000

	PMULHUW AANDC_SHIFT_REG, X0 // X0 = 4 groups of 00000000|00cccccc|00000000|00aaaaaa
	PMULLW  DANDB_SHIFT_REG, X1 // X1 = 4 groups of 00dddddd|00000000|00bbbbbb|00000000
	POR     X1, X0

	// X0 = 4 groups of 00dddddd|00cccccc|00bbbbbb|00aaaaaa
	//
	// Convert these 16 6 bit numbers to b64 codes by adding a shift
	// to each number.  For example, if aaaaaa = 2 we want to add asc('A')
	// to convert it to its base64 encoded value of C, assuming standard
	// encoding.

	MOVOA X0, X1
	MOVOA X0, X3

	// Compute indices for shift lookup table

	PSUBUSB SUB51_REG, X1
	PCMPGTB CMP26_REG, X3
	PSUBSB  X3, X1

	// An example is helpful here
	// X0 = |1|27|54|62|
	// X1 = |0|0|3|11|
	// X3 = |0|-1|-1|-1|
	// X1' = |0|1|4|12|

	MOVOA  B64_LOOKUP_REG, X7
	PSHUFB X1, X7
	PADDSB X7, X0

	// X7 stores values that need to be added to values in X0.
	// Continuing the example with the standard lookup table
	// X7 = |65|71|-4|-19|
	// X0 = |1|27|54|62|
	// X0' = |65+1|27+71|54-3|62-19|, which is ASCII for Bb3+

	MOVOU X0, (R14)(DI*1)

	ADDQ $16, DI
	ADDQ $12, SI

	CMPQ SI, DX
	JLT  read12write16

finish:

	MOVQ DI, di+72(FP)
	MOVQ SI, si+80(FP)

	RET
