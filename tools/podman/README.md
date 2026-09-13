# Containerised GBA build harness

The harness uses a private `localhost/pocket-quartus:25.1std` image built
from Intel's installers. Routine Quartus work runs on controlled runners
through the shared `tools/runner-build` profile `pocket-gba gba`; see
[BUILD-RUNNER.md](../../docs/BUILD-RUNNER.md).

The commands the runner invokes are:

```sh
make gba FITTER_EFFORT="STANDARD FIT" SEED=3
make report
```

`make gba SKIP_COMPILE=1` repackages existing outputs without synthesis. It
does not prove those outputs came from the current checkout. Keep the built
commit and report with the bitstream, and stamp a release from that commit.
`RELEASE_NAME=v0.9999.YYYYMMDD` selects the package version.

| Path under `build/gba/` | Contents |
|---|---|
| `work/` | Source copy, Quartus scratch and compilation outputs |
| `bitstream.rbf_r` | Bit-reversed bitstream for the Pocket |
| `sd/` | Staged Assets, Cores and Platforms |
| `kroy.GBA_<version>.zip` | Installable package |
| `report.txt` | Utilization and worst timing slack across all corners |
| `build.log` | Quartus output |

Fetched jobs may live under `build/watch/`; use the returned job's ZIP and
report together. An old `sd/` tree is not evidence of the package's contents.

`report.sh` rejects negative slack and leaves `TIMING_FAILED` on failure,
even if Quartus exited zero. Host Python utilities use `build/gba/venv`.
The current candidate and measured settings are in
[BASELINE.md](../../docs/BASELINE.md).

Simulation is separate and carries no Quartus files:

```sh
make sim-image
make test
make test CHT_DB=/path/to/cht
```

The image contains Icarus Verilog, GHDL and Python. With no mounted corpus,
the two optional corpus checks report skips. GitHub runs this same suite and
verifies release packages; it never synthesises a core or uploads Quartus.
