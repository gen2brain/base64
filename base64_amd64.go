// Copyright 2017 The Go Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

package base64

//go:noescape
func encode12ByteGroups(lookup []int8, dst, src []byte) (di int, si int)

//go:noescape
func encode24ByteGroups(lookup []int8, dst, src []byte) (di int, si int)

func cpuidSSSE3() bool

func cpuidAVX2() bool

var lookupStd = []int8{
	65, 71, -4, -4, -4, -4, -4, -4, -4, -4, -4, -4, -19, -16, 0, 0,
}

var lookupURL = []int8{
	65, 71, -4, -4, -4, -4, -4, -4, -4, -4, -4, -4, -17, 32, 0, 0,
}

var hasSSSE3 bool

var hasAVX2 bool

func init() {
	hasSSSE3 = cpuidSSSE3()
	hasAVX2 = cpuidAVX2()
}

func encodeAccelerated(enc *Encoding, dst, src []byte) (int, int) {
	// If the source slice is less than 12 bytes fallback to the standard
	// go encoder.
	if len(src) < 12 {
		return 0, 0
	}

	// If our SIMD map is too small or not set fallback to go encoder.
	// This will happen if a non-standard encoding is being used.
	if len(enc.accEncode) < 16 {
		return 0, 0
	}

	// The destination slice is too small.  As the assembly code doesn't
	// check slice bounds we're going to fallback to the go code, which
	// will panic appropriately.
	if len(dst) < enc.EncodedLen(len(src)) {
		return 0, 0
	}

	// AVX2 does the 24-byte groups, SSSE3 a possible trailing 12-byte group,
	// the go encoder the rest. encode12ByteGroups loops once, so guard >= 12.
	di, si := encode24ByteGroups(enc.accEncode, dst, src)
	if len(src)-si >= 12 {
		d, s := encode12ByteGroups(enc.accEncode, dst[di:], src[si:])
		di += d
		si += s
	}

	return di, si
}

func accelerateEncodeMap(encoder string) []int8 {
	switch encoder {
	case encodeStd:
		return lookupStd
	case encodeURL:
		return lookupURL
	}

	return nil
}
