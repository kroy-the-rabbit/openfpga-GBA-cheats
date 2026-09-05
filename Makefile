# Build and test harness for the Pocket GBA core.
#
# Quartus, containerised (see tools/podman/README.md):
#
#   make gba                  build -> build/gba/{bitstream.rbf_r,sd/,*.zip,report.txt}
#   make gba SKIP_COMPILE=1   repackage existing outputs (no Quartus run)
#   make gba SEED=2           re-run the fitter with a different placement seed
#   make report               regenerate build/gba/report.txt from existing outputs
#   make shell                interactive shell in the Quartus container
#
# Simulation for the cheat loaders (see docs/CHEATS.md, docs/CHEATBIN.md and
# tools/sim/). `test` covers both the .chtbin loader the core builds today and
# the .cht parser it replaced, which is still in the tree:
#
#   make sim-image   build the Icarus Verilog container (once, about a minute)
#   make test        the whole suite
#   make test CHT_DB=/path/to/cht        and the cross-check over a corpus
#   make test CHT_DB=... ARGS="-n 100"   sample it instead of all 513 files
#   make sim-shell   interactive shell in the container with the repo at /work
#
#   make clean       remove build/

PODMAN   ?= podman
IMAGE    ?= localhost/pocket-quartus:25.1std
SIMIMAGE ?= localhost/pocket-sim:1
HARNESS  := tools/podman

# CHT_DB mounts a corpus of .cht files for the cross-check. With it unset,
# run.py looks in external/, which is git-ignored.
CHTDB = $(if $(CHT_DB),-v "$(abspath $(CHT_DB)):/cht:ro" -e CHT_DB=/cht,)
SIMRUN = $(PODMAN) run --rm $(PODMAN_TTY) --userns=keep-id \
	--security-opt label=disable \
	-v "$(CURDIR):/work" -w /work -e HOME=/tmp $(CHTDB) $(SIMIMAGE)

.PHONY: gba report shell sim-image test sim-shell clean

gba:
	PODMAN=$(PODMAN) IMAGE=$(IMAGE) SEED=$(SEED) SKIP_COMPILE=$(SKIP_COMPILE) \
	FITTER_EFFORT="$(FITTER_EFFORT)" NPROC="$(NPROC)" \
	RELEASE_NAME=$(RELEASE_NAME) $(HARNESS)/build.sh

report:
	$(HARNESS)/report.sh

shell:
	$(PODMAN) run --rm -it --userns=keep-id --security-opt label=disable \
		-v "$(CURDIR)/build/gba/work:/work" -w /work -e HOME=/tmp $(IMAGE) bash

sim-image:
	$(PODMAN) build --security-opt label=disable -t $(SIMIMAGE) \
		-f $(HARNESS)/Containerfile.sim $(HARNESS)

# The converter tests and the RTL cross-check both want a corpus of .cht files,
# which this repo does not carry: set CHT_DB to a directory of them (see
# docs/CHEATS.md) or those two passes are skipped and the rest still runs.
# ARGS passes through to run.py.
test:
	$(SIMRUN) python3 tools/cheats/test_cht2bin.py --corpus
	$(SIMRUN) python3 tools/sim/run_binloader.py
	$(SIMRUN) python3 tools/sim/run_fixtures.py
	$(SIMRUN) python3 tools/sim/run_e2e.py
	$(SIMRUN) python3 tools/sim/run_cart_rom.py
	$(SIMRUN) python3 tools/sim/run.py $(ARGS)

sim-shell: PODMAN_TTY = -it
sim-shell:
	$(SIMRUN) bash

clean:
	rm -rf build
