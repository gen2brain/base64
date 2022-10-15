// Copyright 2018 The Go Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

#include "textflag.h"

GLOBL ·clearHiMask(SB),RODATA,$16
DATA ·clearHiMask(SB)/8,$0x3f3f3f3f3f3f3f3f
DATA ·clearHiMask+8(SB)/8,$0x3f3f3f3f3f3f3f3f

//func neonEncode(table *[64]byte, dst, src *[]byte, count int)
TEXT ·neonEncode(SB),NOSPLIT,$0
	MOVD	lookup_base+0(FP), R0
	MOVD	dst_base+8(FP), R1
	MOVD	src_base+16(FP), R2
	MOVD	count+24(FP), R3
	MOVD	$·clearHiMask(SB), R4
	VLD1	(R0), [V20.B16, V21.B16, V22.B16, V23.B16]
	VLD1	(R4), [V24.B16]

enc48:
	// Divide bits of three src bytes over four dst bytes
	//VLD3R	(R2),  [V0.B16, V1.B16, V2.B16]
	WORD	$0x4CDF4040
	VSRI	$2, V0.B16, V10.B16
	VSHL	$4, V0.B16, V11.B16
	VSRI	$4, V1.B16, V11.B16
	VSHL	$2, V1.B16, V12.B16
	VSRI	$6, V2.B16, V12.B16
	VMOV	V2.B16, V13.B16

	VAND	V24.B16, V10.B16, V10.B16
	VAND	V24.B16, V11.B16, V11.B16
	VAND	V24.B16, V12.B16, V12.B16
	VAND	V24.B16, V13.B16, V13.B16

	VTBL	V10.B16, [V20.B16, V21.B16, V22.B16, V23.B16], V10.B16
	VTBL	V11.B16, [V20.B16, V21.B16, V22.B16, V23.B16], V11.B16
	VTBL	V12.B16, [V20.B16, V21.B16, V22.B16, V23.B16], V12.B16
	VTBL	V13.B16, [V20.B16, V21.B16, V22.B16, V23.B16], V13.B16

	//st4 { v10.16b, v11.16b, v12.16b, v13.16b }, [x1], #64
	WORD	$0x4C9F002A
	SUB	$1, R3
	CBNZ	R3, enc48
	RET
