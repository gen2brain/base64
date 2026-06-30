// Copyright 2024 The Go Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

package base64

import (
	stdbase64 "encoding/base64"
	"math/rand"
	"testing"
)

// fillPattern fills b with a pattern spanning all 256 byte values.
func fillPattern(b []byte) {
	for i := range b {
		b[i] = byte(i*131 + 17)
	}
}

// encCase pairs an encoding with the stdlib reference it must match byte-for-byte.
type encCase struct {
	name string
	enc  *Encoding
	ref  *stdbase64.Encoding
}

func encCases() []encCase {
	return []encCase{
		{"Std", StdEncoding, stdbase64.StdEncoding},
		{"URL", URLEncoding, stdbase64.URLEncoding},
		{"RawStd", RawStdEncoding, stdbase64.RawStdEncoding},
		{"RawURL", RawURLEncoding, stdbase64.RawURLEncoding},
	}
}

// TestEncodeMatchesStdlib checks every length 0-4096, crossing the 12/24/48
// SIMD block boundaries, byte-for-byte against the stdlib encoder.
func TestEncodeMatchesStdlib(t *testing.T) {
	for _, c := range encCases() {
		for n := 0; n <= 4096; n++ {
			src := make([]byte, n)
			fillPattern(src)

			got := c.enc.EncodeToString(src)
			want := c.ref.EncodeToString(src)
			if got != want {
				t.Fatalf("%s len=%d:\n got=%q\nwant=%q", c.name, n, got, want)
			}
		}
	}
}

// TestEncodeRandom cross-checks random data to catch data-dependent SIMD bugs.
func TestEncodeRandom(t *testing.T) {
	rng := rand.New(rand.NewSource(1))
	for _, c := range encCases() {
		for iter := 0; iter < 2000; iter++ {
			src := make([]byte, rng.Intn(600))
			rng.Read(src)
			if c.enc.EncodeToString(src) != c.ref.EncodeToString(src) {
				t.Fatalf("%s len=%d differs from stdlib:\n %x", c.name, len(src), src)
			}
		}
	}
}

// TestEncodeFrameSized covers JPEG-frame-sized buffers, the cam2ip hot path.
func TestEncodeFrameSized(t *testing.T) {
	for _, c := range encCases() {
		for _, n := range []int{640 * 480 / 4, 640 * 480, 1280 * 720} {
			src := make([]byte, n)
			fillPattern(src)
			if c.enc.EncodeToString(src) != c.ref.EncodeToString(src) {
				t.Fatalf("%s len=%d differs from stdlib", c.name, n)
			}
		}
	}
}

func benchmarkEncode(b *testing.B, n int) {
	src := make([]byte, n)
	fillPattern(src)
	dst := make([]byte, StdEncoding.EncodedLen(n))
	b.SetBytes(int64(n))
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		StdEncoding.Encode(dst, src)
	}
}

func BenchmarkEncode64(b *testing.B)    { benchmarkEncode(b, 64) }
func BenchmarkEncode1K(b *testing.B)    { benchmarkEncode(b, 1024) }
func BenchmarkEncodeFrame(b *testing.B) { benchmarkEncode(b, 640*480) }

func benchmarkStdlibEncode(b *testing.B, n int) {
	src := make([]byte, n)
	fillPattern(src)
	dst := make([]byte, stdbase64.StdEncoding.EncodedLen(n))
	b.SetBytes(int64(n))
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		stdbase64.StdEncoding.Encode(dst, src)
	}
}

func BenchmarkStdlibEncode64(b *testing.B)    { benchmarkStdlibEncode(b, 64) }
func BenchmarkStdlibEncode1K(b *testing.B)    { benchmarkStdlibEncode(b, 1024) }
func BenchmarkStdlibEncodeFrame(b *testing.B) { benchmarkStdlibEncode(b, 640*480) }
