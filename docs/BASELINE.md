# Build measurements

## Current tested build: `cfbfa81`

Quartus Lite 25.1std build 1129, STANDARD FIT, seed 1 on sisko2.
The installed bitstream matches this build by SHA-256 on 2026-09-15.

| ALMs | RAM blocks | Setup | Hold | Recovery | Removal | Minimum pulse width |
|---|---|---|---|---|---|---|
| 15,996 (87 %) | 278 | +0.075 ns | +0.101 ns | +3.873 ns | +1.056 ns | +0.827 ns |

24,402 registers, 26 DSP blocks, 979 s elapsed. Bitstream SHA-256:
`1c11b22d840fd5dee28d0c71b95575f4096224b9fbe8ff0461c7517f3fcd7685`.
Hardware results and limits are in [HARDWARE.md](HARDWARE.md).

## Previous release build: `f2a86db`

Quartus Lite 25.1std build 1129, STANDARD FIT. Seed 3 is the installed,
hardware-tested build; seed 1 is an independent passing fit.

| Seed | ALMs | RAM blocks | Setup | Hold |
|---|---|---|---|---|
| 3 | 16,080 (87 %) | 278 | +0.092 ns | +0.121 ns |
| 1 | 16,089 (87 %) | 278 | +0.045 ns | +0.109 ns |

Seed 3 also passes recovery (+2.935 ns), removal (+0.966 ns) and minimum
pulse width (+0.827 ns), with 24,360 registers and 1121 s elapsed.
The sixteen-slot ROM-patch table, `.cht` parser, named overlay and Fast Burst
profile are included. Bitstream SHA-256:
`489904ea59dea4e1408c770cbe8e853a67741f5817d1884d59e57e77b7d3f31b`.


[Earlier build measurements](https://github.com/kroy-the-rabbit/pocket-engineering/blob/main/gba/docs/BASELINE.md) (private).
