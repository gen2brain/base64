package base64

const (
	srcBlockSize = 48
	dstBlockSize = 64
)

func encodeAccelerated(enc *Encoding, dst, src []byte) (di int, si int) {
	if len(src) < srcBlockSize {
		return
	}
	bc := len(src) / srcBlockSize
	dc := len(dst) / dstBlockSize
	if bc > dc {
		bc = dc
	}
	if bc == 0 {
		return 0, 0
	}
	di, si = dstBlockSize*bc, srcBlockSize*bc
	neonEncode(&enc.encode, &dst[0], &src[0], bc)
	return
}

func neonEncode(table *[64]byte, dst, src *byte, count int)

func accelerateEncodeMap(encoder string) []int8 {
	return nil
}
