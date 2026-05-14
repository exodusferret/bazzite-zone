# Bazzite Zone

Custom Bazzite / `bootc` image for the Zotac Zone.

## What It Is

- Base image: `ghcr.io/ublue-os/bazzite-deck:stable`
- Target device: Zotac Zone
- Purpose:
  - bake Zotac-specific drivers into the image
  - avoid reinstalling out-of-tree modules after every kernel update
  - provide a build path for container, `qcow2`, `raw`, and installer ISO artifacts

## What Is Included

- OpenZotacZone userspace:
  - `/usr/local/bin/openzone_manager.sh`
  - `/usr/local/bin/uninstall_openzone_drivers.sh`
  - `/usr/local/bin/zotac_dial_daemon.py`
- OpenZotacZone kernel modules:
  - `/usr/lib/modules/<kernel>/extra/zotac-zone/*.ko`
  - `/usr/local/lib/zotac-zone/*.ko`
- ElektroCoder EC fan module:
  - `/usr/lib/zotac-zone-fan/zotac-zone-platform.ko`
- CoolerControl daemon AppImage:
  - `/var/opt/coolercontrol/CoolerControlD-x86_64.AppImage`
- Image-managed services:
  - `zotac-zone-drivers.service`
  - `zotac-dials.service`
  - `coolercontrold.service`
  - `zotac-fan.service`
- Secure Boot helper:
  - `/usr/bin/zotac-secureboot-enroll`

## What Works In This Repo

- build Zotac driver artifacts during image build
- install and enable the driver/dial/fan services
- sign kernel modules in release builds when signing secrets are provided
- ship MOK certificate files for Secure Boot enrollment
- build container images in CI
- build `qcow2` and `anaconda-iso` artifacts in CI

## What Users Can Do

- install or boot a disk artifact built from this repo
- use `openzone_manager.sh` for:
  - back button mapping
  - RGB settings
  - dial behavior
  - deadzones
  - vibration
- get a corrected Gamescope HDR display profile installed into
  `~/.config/gamescope/scripts/00-gamescope/displays/zotac.zone.oled.lua` at user login
- use `zotac-secureboot-enroll` on Secure Boot systems

## What Is Not In This Repo

- no repo-managed `144 Hz` fix
- no Decky Loader setup
- no curated Decky plugin set
- no OpenRGB package integration
- no touchpad tuning layer

## Usage

### Built Image

- container image output:
  - from `Containerfile`
- disk image outputs:
  - `qcow2`
  - `raw`
  - `anaconda-iso`

### Install / First Boot

- flash or boot a disk artifact built from this repo
- complete the normal Bazzite first-boot setup
- after the first boot:
  - on Secure Boot systems, enroll the project MOK before expecting the Zotac modules to load
  - on non-Secure-Boot systems, the Zotac modules load without MOK enrollment

### Secure Boot / MOK

- release builds sign the bundled Zotac kernel modules
- certificate paths in the image:
  - `/usr/share/secureboot/zotac-zone-mok.der`
  - `/usr/share/secureboot/zotac-zone-mok.pem`
  - `/etc/pki/akmods/certs/akmods-zotac-zone.der`
- enrollment helper:
  - `/usr/bin/zotac-secureboot-enroll`
- default one-time MOK password:
  - `universalblue`

### Secure Boot Setup

1. Boot the installed image.
2. Run:

```bash
sudo /usr/bin/zotac-secureboot-enroll
```

3. The helper queues the import using the built-in one-time MOK password listed above.
4. Reboot.
5. In MokManager:
   - choose `Enroll MOK`
   - confirm enrollment
   - enter the same one-time MOK password
6. Reboot back into the system.

### Secure Boot Behavior

- if the certificate is already enrolled:
  - `zotac-load-drivers` loads the Zotac modules normally
- if Secure Boot is enabled and the certificate is not enrolled:
  - `zotac-load-drivers` exits without loading the Zotac modules
  - the system tells the user to run `zotac-secureboot-enroll`
- if Secure Boot is disabled:
  - no enrollment is needed

### Manual MOK Enrollment

```bash
sudo mokutil --timeout -1
sudo mokutil --import /etc/pki/akmods/certs/akmods-zotac-zone.der
```

- then reboot
- complete enrollment in MokManager
- use the same one-time password you entered during `mokutil --import`

### On The Installed System

```bash
sudo /usr/local/bin/openzone_manager.sh
```

```bash
sudo /usr/bin/zotac-secureboot-enroll
```

## Developer Setup

### Requirements

- `git`
- `podman`
- `just`
- `sudo`

### Clone

```bash
git clone <repo-url>
cd bazzite-zone
git submodule sync --recursive
git submodule update --init --recursive
```

If an older local submodule config still points `vendor/OpenZotacZone` at the wrong
remote, `git submodule sync --recursive` refreshes it from `.gitmodules`.

If that submodule was already initialized with the legacy remote, reset it directly:

```bash
git -C vendor/OpenZotacZone remote set-url origin https://github.com/exodusferret/ZotacZone-Drivers.git
```

If you want the latest `main` from `exodusferret/ZotacZone-Drivers` rather than this
repository's pinned submodule commit, use:

```bash
git submodule update --init --recursive --remote
```

### Local Build

```bash
just build
```

### Local Disk Artifacts

```bash
just build-qcow2
just build-raw
just build-iso
```

### Local VM Run

```bash
just run-vm-qcow2
just run-vm-raw
just run-vm-iso
```

### Developer Commands

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

## Build Layout

- [Containerfile](/home/NLAB.local/nico/projects/bazzite-zone/Containerfile:1)
  - image definition
  - artifact stage
  - final image stage
- [build_files/build-modules.sh](/home/NLAB.local/nico/projects/bazzite-zone/build_files/build-modules.sh:1)
  - build OpenZotacZone modules
  - build ElektroCoder EC module
  - download CoolerControl
  - optional Secure Boot signing
- [build_files/configure-image.sh](/home/NLAB.local/nico/projects/bazzite-zone/build_files/configure-image.sh:1)
  - install runtime packages
  - install services and helper scripts
  - enable services
- [build_files/run-bootc-image-builder.sh](/home/NLAB.local/nico/projects/bazzite-zone/build_files/run-bootc-image-builder.sh:1)
  - build disk artifacts from a container image
- [Justfile](/home/NLAB.local/nico/projects/bazzite-zone/Justfile:1)
  - local build and VM commands

## CI

- [build.yml](/home/NLAB.local/nico/projects/bazzite-zone/.github/workflows/build.yml:1)
  - build container image
  - push to GHCR on default-branch non-PR builds
  - Cosign signing
  - Secure Boot signing inputs
- [build-disk.yml](/home/NLAB.local/nico/projects/bazzite-zone/.github/workflows/build-disk.yml:1)
  - build `qcow2` and `anaconda-iso`
  - optional S3 upload

### Required Secrets

- `SIGNING_SECRET`
- `COSIGN_PASSWORD`
- `SECUREBOOT_MOK_KEY`
- `SECUREBOOT_MOK_CERT`

### Optional Secrets

- `S3_PROVIDER`
- `S3_ACCESS_KEY_ID`
- `S3_SECRET_ACCESS_KEY`
- `S3_REGION`
- `S3_ENDPOINT`
- `S3_BUCKET_NAME`

## Third-Party Code And Licenses

### Repo License

- repo-owned files: Apache-2.0
- file: [LICENSE](/home/NLAB.local/nico/projects/bazzite-zone/LICENSE:1)

### Included / Vendored Projects

- `exodusferret/ZotacZone-Drivers`
  - location: `vendor/OpenZotacZone`
  - role:
    - source for HID/platform modules
    - source for `openzone_manager.sh`
    - source for `uninstall_openzone_drivers.sh`
    - source for `zotac_dial_daemon.py` extraction
  - license: GPL-3.0
  - distributed in built image: yes

- `ElektroCoder-zotac-zone-platform`
  - location: `vendor/ElektroCoder-zotac-zone-platform`
  - role:
    - source for `zotac-zone-platform.ko`
  - license:
    - not declared in this repo copy
    - treat as third-party source input
  - distributed in built image:
    - built kernel module

- `CoolerControl`
  - source:
    - downloaded during build from pinned release URL in `build_files/dependencies.env`
  - role:
    - fan control daemon AppImage
  - license:
    - not declared in this repo
    - upstream project license applies
  - distributed in built image: yes

- `Universal Blue / Bazzite`
  - role:
    - base image and bootc workflow foundation
  - integrated as:
    - base image `ghcr.io/ublue-os/bazzite-deck:stable`
  - vendored in this repo: no

### License Handling In Built Image

- OpenZotacZone GPL license copied to:
  - `/usr/share/licenses/bazzite-zone/OpenZotacZone-GPL-3.0.txt`
- OpenZotacZone source metadata written to:
  - `/usr/share/doc/bazzite-zone/openzotaczone-source-info.txt`
- OpenZotacZone corresponding source bundle written to:
  - `/usr/share/doc/bazzite-zone/openzotaczone-corresponding-source.tar.gz`

- project notice file:
  - [THIRD_PARTY_NOTICES.md](/home/NLAB.local/nico/projects/bazzite-zone/THIRD_PARTY_NOTICES.md:1)

## Notes

- `disk_config/iso-gnome.toml` exists, but current local and CI flows use `iso-kde.toml`
- README scope:
  - only features wired by this repo
  - no claims for base-image behavior not implemented here
