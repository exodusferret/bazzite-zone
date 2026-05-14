## Build Notes

This file documents the build flow that is actually implemented in this repository.
It is based on the checked-in `Containerfile`, `Justfile`, build scripts, and GitHub workflows.

## Managed Inputs

The image build consumes pinned repository inputs from the working tree:

- `vendor/OpenZotacZone`: `exodusferret/ZotacZone-Drivers` git submodule
- `vendor/ElektroCoder-zotac-zone-platform`: ElektroCoder EC platform driver git submodule
- `build_files/dependencies.env`: regex-managed version pins such as `COOLERCONTROL_VERSION`

Initialize submodules after cloning:

```bash
git submodule update --init --recursive
```

## What The Repo Builds

- a `bootc` container image from `Containerfile`
- out-of-tree Zotac kernel modules in a dedicated artifact stage
- optional disk artifacts from that image:
  - `qcow2`
  - `raw`
  - `anaconda-iso`

The image build has two major stages:

- `artifact-builder`: compiles OpenZotacZone and ElektroCoder modules, installs upstream userspace scripts, downloads CoolerControl, fetches and patches the Zotac Gamescope HDR display script, optionally signs modules
- final image stage: copies artifacts into a `ghcr.io/ublue-os/bazzite-deck:stable` base image and runs `build_files/configure-image.sh`

## Current Defaults

- image name: `bazzite_zone`
- default tag: `latest`
- default local builder image: `quay.io/centos-bootc/bootc-image-builder:latest`
- default base image: `ghcr.io/ublue-os/bazzite-deck:stable`

If you rename the image, keep `Justfile`, `.github/workflows/build.yml`, and `.github/workflows/build-disk.yml` in sync.

## Local Workflows

Available `just` entry points:

- `just build`
- `just build-qcow2`
- `just build-raw`
- `just build-iso`
- `just rebuild-qcow2`
- `just rebuild-raw`
- `just rebuild-iso`
- `just run-vm-qcow2`
- `just run-vm-raw`
- `just run-vm-iso`
- `just spawn-vm`
- `just lint`
- `just format`

Build the container image locally:

```bash
just build
```

Equivalent direct `podman` build:

```bash
podman build -t localhost/bazzite_zone:latest .
```

To mirror CI more closely, pass Secure Boot build args:

```bash
podman build \
  --build-arg SECUREBOOT_MOK_KEY_B64="$(base64 -w0 < secureboot/MOK.priv)" \
  --build-arg SECUREBOOT_MOK_CERT_B64="$(base64 -w0 < secureboot/MOK.pem)" \
  -t localhost/bazzite_zone:latest .
```

Notes:

- submodule revisions are taken from the checked-out `vendor/` directories
- `just build` also passes `OPENZOTAC_REV` and `ELEKTROCODER_REV` when the submodules exist
- omit Secure Boot args if you do not want local modules to be signed

## Local Disk Image Build

The repo provides both `just` wrappers and a lower-level helper:

```bash
just build-qcow2
just build-raw
just build-iso
```

These routes eventually call `build_files/run-bootc-image-builder.sh`, which:

- retries `podman pull` for the builder image
- retags the builder image locally as `localhost/bootc-image-builder:ci`
- pulls the target image only if it is not already present locally
- runs the builder with `--pull=never`

Direct helper example for an ISO:

```bash
mkdir -p ~/image-output
./build_files/run-bootc-image-builder.sh \
  quay.io/centos-bootc/bootc-image-builder:latest \
  localhost/bazzite_zone:latest \
  anaconda-iso \
  "$PWD/disk_config/iso-kde.toml" \
  "$HOME/image-output" \
  btrfs
```

Direct helper example for a `qcow2` image:

```bash
mkdir -p ~/image-output
./build_files/run-bootc-image-builder.sh \
  quay.io/centos-bootc/bootc-image-builder:latest \
  localhost/bazzite_zone:latest \
  qcow2 \
  "$PWD/disk_config/disk.toml" \
  "$HOME/image-output" \
  btrfs
```

The direct helper accepts a configurable filesystem via its `rootfs` argument. The `just` helper currently passes `btrfs` for its local disk-image path.

## CI Workflows

Implemented workflows:

- `.github/workflows/build.yml`
- `.github/workflows/build-disk.yml`

`build.yml` currently:

- runs on pull requests to `main`, pushes to `main`, and manual dispatch
- ignores pure `README.md` changes on push
- checks out submodules recursively
- prepares image metadata labels
- requires Secure Boot secrets for non-PR builds on the default branch
- builds the container image with `buildah`
- pushes to GHCR on non-PR builds of the default branch
- signs published container images with Cosign on non-PR builds of the default branch

`build-disk.yml` currently:

- runs manually
- runs after the container workflow completes
- runs on pull requests when `disk_config/disk.toml`, `disk_config/iso-kde.toml`, or the workflow file itself changes
- builds `qcow2` and `anaconda-iso`
- uploads either to GitHub Actions artifacts or to S3-compatible storage

## Required Secrets

For non-PR builds of the default branch in `build.yml`:

- `SIGNING_SECRET`
- `COSIGN_PASSWORD`
- `SECUREBOOT_MOK_KEY`
- `SECUREBOOT_MOK_CERT`

For optional S3 upload in `build-disk.yml`:

- `S3_PROVIDER`
- `S3_ACCESS_KEY_ID`
- `S3_SECRET_ACCESS_KEY`
- `S3_REGION`
- `S3_ENDPOINT`
- `S3_BUCKET_NAME`

## Secure Boot Notes

When signing inputs are provided, the build places the certificate at:

- `/usr/share/secureboot/zotac-zone-mok.der`
- `/usr/share/secureboot/zotac-zone-mok.pem`
- `/etc/pki/akmods/certs/akmods-zotac-zone.der`

The image also installs `/usr/bin/zotac-secureboot-enroll`, which queues MOK enrollment with `mokutil`.
The helper suggests the one-time password `universalblue`.

## TODO

No explicit build-flow claims were found in this README that are entirely absent from the repository, but two scope limits are worth keeping visible:

- `disk_config/iso-gnome.toml` exists in the repo, but the current `Justfile` and CI workflows only wire `iso-kde.toml`
- this document reflects static repo analysis; it does not guarantee that every build path succeeds in every external environment or with every upstream image revision
