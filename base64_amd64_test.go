// Copyright 2017 The Go Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

package base64

import "testing"

func TestEncodeAccelerated(t *testing.T) {
	dst := make([]byte, 1)
	src := make([]byte, 12)
	si, di := encodeAccelerated(StdEncoding, dst, src)
	if si != 0 || di != 0 {
		t.Errorf("encodeAccelerated expected to return (0,0) when dst is too small.  Got (%d %d)", si, di)
	}
}
