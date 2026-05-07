## Build Notes

This file documents the current local and CI build flow for this repository.
Use placeholder values such as `<repo-owner>`, `<repo-name>`, and `<image-name>`
when adapting commands to another fork.

## Managed Upstream Inputs

The image now treats the Zotac-specific upstream sources as pinned repository
inputs instead of resolving them dynamically during the workflow:

- `vendor/OpenZotacZone`: `OpenZotacZone/ZotacZone-Drivers` git submodule
- `vendor/ElektroCoder-zotac-zone-platform`: ElektroCoder gist git submodule
- `build_files/dependencies.env`: version pins such as `COOLERCONTROL_VERSION`

Initialize the vendored sources after cloning:

```bash
git submodule update --init --recursive
```

Update behavior:

- Dependabot can update `.gitmodules` targets through the `gitsubmodule` ecosystem.
- Renovate can update the same submodules and regex-managed version pins such as `COOLERCONTROL_VERSION`.
- Rebuilds now happen from dependency PRs or direct repo changes, rather than from a scheduled remote source probe.

## What The Repo Builds

- A bootc container image from `Containerfile`
- A signed out-of-tree kernel module set for the target image
- Optional disk artifacts from the container image:
  - `qcow2`
  - `anaconda-iso`

The primary CI workflows are:

- `.github/workflows/build.yml`
- `.github/workflows/build-disk.yml`

## Current Image Defaults

- Image registry: `ghcr.io/<repo-owner>`
- Image name: `bazzite_zone`
- Default tag: `latest`
- Disk build source image: `ghcr.io/<repo-owner>/bazzite_zone:latest`

If you rename the image, keep `build.yml`, `build-disk.yml`, and any local commands in sync.

## Local Container Build

Build the container image locally:

```bash
podman build -t localhost/bazzite_zone:latest .
```

This builds the same `Containerfile` used by CI, including:

- external module compilation
- Secure Boot module signing when signing inputs are provided
- image configuration from `build_files/configure-image.sh`

To mirror CI more closely, you can also pass the optional build arguments:

```bash
podman build \
  --build-arg SECUREBOOT_MOK_KEY_B64="$(base64 -w0 < secureboot/MOK.priv)" \
  --build-arg SECUREBOOT_MOK_CERT_B64="$(base64 -w0 < secureboot/MOK.pem)" \
  -t localhost/bazzite_zone:latest .
```

Notes:

- The exact `OpenZotacZone` and `ElektroCoder` source revisions come from the checked-out git submodules under `vendor/`.
- Omit the Secure Boot arguments if you do not want locally built modules to be signed.

## Local Disk Image Build

The repository CI uses `osbuild/bootc-image-builder-action` to generate disk images.
For a local equivalent, first build or pull the container image, then run a bootc image
builder container against it.

Example using the ISO config:

```bash
mkdir -p ~/image-output
sudo podman run --rm -it --privileged \
  -v /var/lib/containers/storage:/var/lib/containers/storage \
  -v ~/image-output:/output \
  -v "$PWD/disk_config/iso-kde.toml:/config.toml:ro" \
  quay.io/centos-bootc/bootc-image-builder:latest \
  --type anaconda-iso \
  --rootfs xfs \
  --config /config.toml \
  --output /output \
  localhost/bazzite_zone:latest
```

Example using the disk config:

```bash
mkdir -p ~/image-output
sudo podman run --rm -it --privileged \
  -v /var/lib/containers/storage:/var/lib/containers/storage \
  -v ~/image-output:/output \
  -v "$PWD/disk_config/disk.toml:/config.toml:ro" \
  quay.io/centos-bootc/bootc-image-builder:latest \
  --type qcow2 \
  --rootfs xfs \
  --config /config.toml \
  --output /output \
  localhost/bazzite_zone:latest
```

Adjust the image reference if you want to build from a remote registry image instead of `localhost`.

## CI Behavior

`build.yml`:

- builds the container image on pushes to `main`, pull requests, and manual dispatch
- consumes dependency revisions from checked-in submodules and version files
- pushes to `ghcr.io/<repo-owner>` only on non-PR builds of the default branch
- signs the pushed container image with Cosign on non-PR builds of the default branch
- signs the out-of-tree kernel modules for Secure Boot on non-PR builds of the default branch when signing secrets are configured
- records build metadata labels such as the upstream OpenZotac commit, ElektroCoder commit, and CoolerControl download URL on the published image

`build-disk.yml`:

- can be run manually
- also runs automatically after a successful container-image workflow
- also runs on pull requests that change `disk_config/*` or `.github/workflows/build-disk.yml`
- produces `qcow2` and `anaconda-iso`
- can upload artifacts either to GitHub Actions artifacts or to S3-compatible storage

## Required Repository Secrets

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

The out-of-tree modules are signed during image build and the public certificate is placed in:

- `/usr/share/secureboot/zotac-zone-mok.der`
- `/usr/share/secureboot/zotac-zone-mok.pem`
- `/etc/pki/akmods/certs/akmods-zotac-zone.der`

The image includes `/usr/bin/zotac-secureboot-enroll`, which queues MOK enrollment with `mokutil` in a Bazzite-compatible way.
By default, the expected one-time MokManager password is `universalblue`.

This enrolls this repository's Secure Boot certificate. It does not reuse or replace another project's certificate.

## Neutral Placeholder Examples

Clone a fork locally:

```bash
git clone https://github.com/<repo-owner>/<repo-name>.git
cd <repo-name>
```

Pull a published image from GHCR:

```bash
sudo podman pull ghcr.io/<repo-owner>/<image-name>:latest
```

Tag it for local bootc image builds:

```bash
sudo podman tag ghcr.io/<repo-owner>/<image-name>:latest localhost/<image-name>:latest
```

## Notes

- Avoid committing private signing material such as `cosign.key` or `secureboot/MOK.priv`.
- The canonical project-level setup and secret-generation commands live in `README.md`.
