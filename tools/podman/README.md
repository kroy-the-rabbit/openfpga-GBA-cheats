# Containerised Quartus build

Quartus never gets installed on the host. `make gba` runs upstream's own
`generate.tcl` inside `docker.io/raetro/quartus:21.1` against a copy of the
tree, then packages an SD-ready folder and gates the result on timing.

    make gba                  build -> build/gba/
    make gba SEED=2           re-run the fitter with another placement seed
    make gba SKIP_COMPILE=1   repackage existing outputs, no Quartus run
    make report               regenerate build/gba/report.txt
    make shell                shell in the container, tree at /work
    make clean                remove build/

Outputs land in `build/gba/`:

| Path | What |
|---|---|
| `work/` | the copy Quartus compiles, including its `db/` scratch, kept between runs so incremental compiles work |
| `bitstream.rbf_r` | bit-reversed bitstream, the form the Pocket loads |
| `sd/` | copy `Assets/`, `Cores/`, `Platforms/` to the card root |
| `*.zip` | the same tree zipped |
| `report.txt` | utilization, worst slack per analysis type, full fit and STA summaries |
| `build.log` | Quartus output |

## Why it is built this way

- **Quartus 21.1, not 25.1.** Upstream tunes constraints, seeds and its custom
  STA reports against 21.1, and this design closes setup by 0.102 ns on
  `clk_sys` in upstream's own CI build. A toolchain bump is a change to the
  result, not a neutral upgrade. The sibling GBC fork uses 25.1; keep them
  apart.
- **The build runs against a copy.** `build/gba/work` is what Quartus writes to,
  so the checked-in tree stays clean and the harness can patch fitter settings
  (processor count, seed) without touching files that CI and upstream share.
- **The harness gates on slack.** Quartus exits 0 on a design that misses
  timing. `report.sh` re-reads `ap_core.sta.summary`, takes the worst slack
  across every corner and analysis type, and exits 3 if it is negative, leaving
  a `TIMING_FAILED` marker next to the report. This is the lesson the GBC fork
  learned by shipping a build with -3.374 ns of setup slack that Quartus called
  a success.
- **Python runs from a venv** at `build/gba/venv`. Nothing is installed into it;
  `scripts/reverse_bitstream.py` is stdlib only and the venv keeps it that way.

## If the image will not pull

`podman pull docker.io/raetro/quartus:21.1` can fail with

    unable to retrieve auth token: invalid username/password

when `~/.docker/config.json` holds a stale docker.io login. The image is public,
so pull anonymously instead:

    printf '{"auths":{}}' > /tmp/anon-auth.json
    podman pull --authfile /tmp/anon-auth.json docker.io/raetro/quartus:21.1

Nothing else in the harness needs credentials once the image is local.
