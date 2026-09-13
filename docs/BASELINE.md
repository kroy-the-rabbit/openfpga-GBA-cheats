# Build measurements

## Tested build: `f2a86db`

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
