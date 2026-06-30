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

// func encode24ByteGroups(lookup []int8, dst, src []byte) (di int, si int)
//
// AVX2 variant of encode12ByteGroups: the same SSSE3 algorithm run lane-local
// on both 128-bit lanes at once (24 src bytes in, 32 dst out per iteration),
// with the same 16-byte constants broadcast to both lanes.
TEXT ·encode24ByteGroups(SB), NOSPLIT, $0-88
	NO_LOCAL_POINTERS

	XORQ SI, SI
	XORQ DI, DI

	TESTB $1, ·hasAVX2(SB)
	JZ    finish24

	MOVQ src_len+56(FP), R10
	MOVQ src_base+48(FP), R8
	MOVQ dst_base+24(FP), R9
	MOVQ lookup_base+0(FP), R12

	VBROADCASTI128 bShuffleMask<>+0(SB), Y8
	VBROADCASTI128 bAAndCMask<>+0(SB), Y9
	VBROADCASTI128 bAAndCShift<>+0(SB), Y10
	VBROADCASTI128 bDAndBMask<>+0(SB), Y11
	VBROADCASTI128 bDAndBShift<>+0(SB), Y12
	VBROADCASTI128 bSub51Mask<>+0(SB), Y13
	VBROADCASTI128 bCmp26Mask<>+0(SB), Y14
	VBROADCASTI128 (R12), Y6

read24write32:
	LEAQ 24(SI), AX
	CMPQ AX, R10
	JGT  done24

	// Low lane src[0:16] (0:12 used); high lane src[12:24] via an 8+4 load
	// so we never read past the buffer.
	VMOVDQU     (R8)(SI*1), X0
	VMOVQ       12(R8)(SI*1), X1
	MOVL        20(R8)(SI*1), AX
	VPINSRD     $2, AX, X1, X1
	VINSERTI128 $1, X1, Y0, Y0

	VPSHUFB Y8, Y0, Y0

	VPAND    Y9, Y0, Y1
	VPAND    Y11, Y0, Y2
	VPMULHUW Y10, Y1, Y1
	VPMULLW  Y12, Y2, Y2
	VPOR     Y2, Y1, Y0

	VPSUBUSB Y13, Y0, Y1
	VPCMPGTB Y14, Y0, Y3
	VPSUBSB  Y3, Y1, Y1

	VPSHUFB Y1, Y6, Y7
	VPADDSB Y7, Y0, Y0

	VMOVDQU Y0, (R9)(DI*1)

	ADDQ $32, DI
	ADDQ $24, SI
	JMP  read24write32

done24:
	VZEROUPPER

finish24:
	MOVQ DI, di+72(FP)
	MOVQ SI, si+80(FP)

	RET

// func cpuidSSSE3() bool
//
// SSSE3 is reported by CPUID function 1, ECX bit 9.
TEXT ·cpuidSSSE3(SB), NOSPLIT, $0-1
	MOVL $1, AX
	MOVL $0, CX
	CPUID
	BTL  $9, CX
	JNC  no_ssse3
	MOVB $1, ret+0(FP)
	RET

no_ssse3:
	MOVB $0, ret+0(FP)
	RET

// func cpuidAVX2() bool
//
// AVX2 requires CPUID function 7 (EBX bit 5), plus OSXSAVE (function 1, ECX bit
// 27) and XCR0 bits 1 and 2 set, so the OS preserves the YMM registers.
TEXT ·cpuidAVX2(SB), NOSPLIT, $0-1
	MOVL $0, AX
	CPUID
	CMPL AX, $7
	JL   no_avx2

	MOVL $1, AX
	MOVL $0, CX
	CPUID
	BTL  $27, CX
	JNC  no_avx2

	MOVL  $0, CX
	XGETBV
	ANDL  $6, AX
	CMPL  AX, $6
	JNE   no_avx2

	MOVL $7, AX
	MOVL $0, CX
	CPUID
	BTL  $5, BX
	JNC  no_avx2

	MOVB $1, ret+0(FP)
	RET

no_avx2:
	MOVB $0, ret+0(FP)
	RET
