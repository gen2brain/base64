// Copyright 2017 The Go Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

// +build !amd64,!arm64

package base64

func encodeAccelerated(enc *Encoding, dst, src []byte) (int, int) {
	return 0, 0
}

func accelerateEncodeMap(encoder string) []int8 {
	return nil
}
