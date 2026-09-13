# Controlled build runners

Routine GBA synthesis and fitting run through the ecosystem's shared
`tools/runner-build` interface, never on the workstation or GitHub Actions.
The profile is `pocket-gba gba`. The current image is private
`localhost/pocket-quartus:25.1std`, Quartus Lite build 1129.

From the GBA checkout in the ecosystem, substitute a registered runner and
unique build name:

```sh
../tools/runner-build status
../tools/runner-build current
SEED=3 FITTER_EFFORT="STANDARD FIT" ../tools/runner-build start RUNNER pocket-gba gba BUILD HEAD
../tools/runner-build job RUNNER pocket-gba gba BUILD HEAD
../tools/runner-build fetch RUNNER pocket-gba gba BUILD HEAD
```

`start` sends the exact committed source to an isolated checkout. Working-tree
changes are not included. Each runner permits one fit; a busy runner is a
refusal, not permission to start another job manually. Keep the source commit
fixed when using `job` and `fetch`.

`fetch` retrieves build results under `build/`; it does not refresh every old
`sd/` tree or `output_files` directory. Select the ZIP and report for the same
job, inspect every timing category, and install from that ZIP. Compare the
card's bitstream hash to the archive. The current tested build and its
artifact directory are in [HANDOFF.md](HANDOFF.md).

GitHub builds only the simulation image (`make sim-image`) and runs
`make test`. Releases are signed tags on `main` plus tested packages,
checksums and reports; CI verifies them. The Quartus image and its archive
stay private and are never uploaded as CI artifacts or to a registry.


[Runner provisioning history](https://github.com/kroy-the-rabbit/pocket-engineering/blob/main/gba/docs/BUILD-RUNNER.md) (private).
