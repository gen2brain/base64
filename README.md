## base64
[![Build Status](https://github.com/gen2brain/base64/actions/workflows/build.yml/badge.svg)](https://github.com/gen2brain/base64/actions)
[![Go Reference](https://pkg.go.dev/badge/github.com/gen2brain/base64.svg)](https://pkg.go.dev/github.com/gen2brain/base64)

SIMD-accelerated drop-in replacement for the standard library `encoding/base64`.

The encode path is vectorized with **AVX2/SSSE3** on `amd64` and **NEON** on
`arm64`, selected at runtime; other architectures fall back to the standard
library encoder. Decoding is the unmodified standard library implementation.

### Performance

Throughput of `Encode` versus the standard library, by input size.

`amd64` - Intel Core i7-1185G7:

| size    | stdlib    | SSSE3      | AVX2                   |
|---------|-----------|------------|------------------------|
| 64 B    | 1254 MB/s | 3030 MB/s  | 3595 MB/s              |
| 1 KiB   | 1473 MB/s | 9177 MB/s  | 13324 MB/s             |
| 300 KiB | 1495 MB/s | 10277 MB/s | 17094 MB/s (**11.4×**) |

`arm64` - Raspberry Pi 5 (Cortex-A76):

| size    | stdlib   | NEON                 |
|---------|----------|----------------------|
| 64 B    | 669 MB/s | 1354 MB/s            |
| 1 KiB   | 716 MB/s | 4812 MB/s            |
| 300 KiB | 710 MB/s | 5507 MB/s (**7.8×**) |

```
go test -run x -bench Encode -benchmem
```
