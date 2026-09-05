# Stand up a Quartus build runner on a Proxmox node

Goal: an LXC on a Proxmox node that runs this repo's containerised Quartus
build, so builds stop competing with a workstation.

Done once already, and that run is the reference. Everything below, including
the three failure modes, is what it actually hit rather than what the
documentation says should happen. Written so this can be followed against any
node with no context from that session.

Substitute your own node for `<NODE>` and an unused container id for `<VMID>`
throughout.

## Why bother, and what to expect

Quartus fitting parallelises poorly - several stages are single-threaded and
gains flatten around 4-8 processors. Do **not** size this for core count.
Measured on the GBA core, same design, same fitter effort:

| Host | Cores used | Elapsed |
|---|---|---|
| GitHub runner | 4 | 1235 s |
| Workstation (Core Ultra 7 155U) | 12 | 2680 s |

The 4-core runner was 2.2x faster than 12 threads of a laptop part, because a
15 W chip throttles under a 40-minute sustained fit and a server does not. The
win from a node is sustained clocks and not tying up a desk machine; the
second win is running several experiments at once.

## 0. Survey the node first

    ssh root@<NODE> 'nproc; free -g | head -2; uptime; \
      lscpu | grep -E "^Model name|^CPU max MHz"; pvesm status; \
      { qm list; pct list; } 2>/dev/null | awk "NR>1{print \$1}" | sort -n'

Check: load average (a node at load 13 is not idle), free space on the storage
you will put the rootfs on, and which VMIDs are taken. Pick an unused one.

## 1. Create the container

    ssh root@<NODE> 'pct create <VMID> \
      /var/lib/vz/template/cache/debian-12-standard_12.2-1_amd64.tar.zst \
      --hostname quartus-build \
      --cores 16 --memory 32768 --swap 4096 \
      --rootfs local-zfs:80 \
      --features nesting=1,keyctl=1,fuse=1 \
      --unprivileged 1 \
      --net0 name=eth0,bridge=vmbr0,tag=50,ip=dhcp,type=veth \
      --onboot 0'
    ssh root@<NODE> 'pct start <VMID>'

Three things in there are load-bearing:

- **`tag=50`.** vmbr0 untagged has no DHCP on this network; the container comes
  up with no address and every apt fetch fails with "Temporary failure
  resolving". 50 is the management VLAN. Confirm with
  `pct exec <VMID> -- ip -4 -o addr show eth0`.
- **`nesting=1,keyctl=1`** so podman runs inside an unprivileged LXC at all.
- **`fuse=1`** for the next section. Adding it later needs a reboot, so put it
  in at create time.

80 GB rootfs is not generous: the Quartus image alone is 12.4 GB and each
build tree is several more.

## 2. Install the toolchain

    pct exec <VMID> -- bash -lc 'export DEBIAN_FRONTEND=noninteractive
      apt-get update -qq
      apt-get install -y -qq --no-install-recommends \
        podman fuse-overlayfs git make rsync zip python3 python3-venv \
        ca-certificates uidmap'

## 3. Point podman at fuse-overlayfs

**This is the failure that will stop you if you skip it.** A ZFS-backed rootfs
cannot host podman's overlay driver:

    Error: 'overlay' is not supported over zfs, a mount_program is required

Write `/etc/containers/storage.conf`:

    [storage]
    driver = "overlay"
    runroot = "/run/containers/storage"
    graphroot = "/var/lib/containers/storage"

    [storage.options.overlay]
    mount_program = "/usr/bin/fuse-overlayfs"

Then `rm -rf /var/lib/containers/storage` so it is rebuilt, and confirm with
`podman info --format '{{.Store.GraphDriverName}}'` -> `overlay`.

Write that file with `pct push`, or base64 it. Do not try to `printf` it
through `ssh -> pct exec -> bash -lc`: the quoting is eaten by three shells and
you get a TOML parse error on line 1.

## 4. Build the Quartus image and prove it runs

Not pulled. Quartus Lite needs no licence file, but that grants no right to
redistribute its installed files, so the image a runner uses is assembled on
the runner from Intel's own installers and stays there: never pushed to a
registry, never attached to a CI artifact. The recipe, the two vendor inputs
and their published hashes, and the explicit licence-acceptance step live in
the private orchestrator under `tools/quartus-image/`; the image it produces
is `localhost/pocket-quartus:<version>`.

    pct exec <VMID> -- bash -lc 'podman run --rm localhost/pocket-quartus:25.1std quartus_sh --version'

Match whatever version the repo's own harness pins, and read `docs/BASELINE.md`
before changing it: constraints and seeds are tuned against a specific one,
and a toolchain move is measured, not assumed.

## 5. Make the build script survive running as root

**The second failure that will stop you.** Build scripts written for a
workstation pass `--userns=keep-id` to podman, which is rootless-only. In an
LXC where everything runs as root it fails before Quartus starts:

    Error: keep-id is only supported in rootless mode
    quartus failed (rc=125)

Fix it in the repo, not on the runner - key the flags on the uid as well as
the runtime. In this repo it is `tools/podman/build.sh`:

    case "$(basename "$PODMAN"):$(id -u)" in
      docker:*) RUNAS=(--user "$(id -u):$(id -g)") ;;
      *:0)      RUNAS=(--security-opt label=disable) ;;
      *)        RUNAS=(--userns=keep-id --security-opt label=disable) ;;
    esac

Root podman already maps container root to host root, so the ownership problem
keep-id solves does not exist there.

## 6. Clone and build

    pct exec <VMID> -- bash -lc 'cd /root && git clone <REPO_URL> work
      cd work && FITTER_EFFORT="STANDARD FIT" NPROC=16 make <target>'

For an unpushed branch, avoid distributing SSH keys: bundle it, `scp` to the
node, `pct push` into the container, fetch from the bundle.

    git bundle create /tmp/b.bundle main..<branch>
    scp /tmp/b.bundle root@<NODE>:/tmp/
    ssh root@<NODE> 'pct push <VMID> /tmp/b.bundle /root/b.bundle'
    pct exec <VMID> -- bash -lc 'cd /root/work && git fetch /root/b.bundle <branch> \
      && git reset --hard FETCH_HEAD'

Run long builds detached, or the ssh session owns them:

    nohup env FITTER_EFFORT="STANDARD FIT" NPROC=16 make <target> \
      > /root/build.log 2>&1 < /dev/null &

## 7. On NPROC

Set it to the container's core count and stop thinking about it. On the GBA
core, `NPROC=4` and `NPROC=12` produced **identical** fit results - 16,689
ALMs, 282 RAM blocks, +0.090 ns setup - so it changes wall clock only, and not
by much. Pin `FITTER_EFFORT` instead: that one genuinely changes the answer.

## Checklist

- [ ] node surveyed, VMID free, load low, disk sufficient
- [ ] container on VLAN 50 with an IP and working DNS
- [ ] `nesting=1,keyctl=1,fuse=1`
- [ ] `podman info` reports the overlay driver via fuse-overlayfs
- [ ] `quartus_sh --version` prints the version the repo expects
- [ ] build script handles root podman
- [ ] a build completes and its report matches a known-good result
