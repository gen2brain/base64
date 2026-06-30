// Copyright 2024 The Go Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

package base64

import "testing"

// TestNeonPathTaken confirms a full 48-byte block is routed through neonEncode.
func TestNeonPathTaken(t *testing.T) {
	src := make([]byte, srcBlockSize)
	dst := make([]byte, StdEncoding.EncodedLen(len(src)))
	di, si := encodeAccelerated(StdEncoding, dst, src)
	if si != srcBlockSize || di != dstBlockSize {
		t.Fatalf("neon path not taken: di=%d si=%d, want di=%d si=%d", di, si, dstBlockSize, srcBlockSize)
	}
}
