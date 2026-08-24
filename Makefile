# Containerised Quartus build for the Pocket GBA core. See tools/podman/README.md.
#
#   make gba                  build -> build/gba/{bitstream.rbf_r,sd/,*.zip,report.txt}
#   make gba SKIP_COMPILE=1   repackage existing outputs (no Quartus run)
#   make gba SEED=2           re-run the fitter with a different placement seed
#   make report               regenerate build/gba/report.txt from existing outputs
#   make shell                interactive shell in the Quartus container
#   make clean                remove build/

PODMAN ?= podman
IMAGE  ?= docker.io/raetro/quartus:21.1
HARNESS := tools/podman

.PHONY: gba report shell clean

gba:
	PODMAN=$(PODMAN) IMAGE=$(IMAGE) SEED=$(SEED) SKIP_COMPILE=$(SKIP_COMPILE) \
	FITTER_EFFORT="$(FITTER_EFFORT)" NPROC="$(NPROC)" \
	RELEASE_NAME=$(RELEASE_NAME) $(HARNESS)/build.sh

report:
	$(HARNESS)/report.sh

shell:
	$(PODMAN) run --rm -it --userns=keep-id --security-opt label=disable \
		-v "$(CURDIR)/build/gba/work:/work" -w /work -e HOME=/tmp $(IMAGE) bash

clean:
	rm -rf build
