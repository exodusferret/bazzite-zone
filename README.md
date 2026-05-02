# OpenZotacZone Bazzite Image for the Zotac Zone Handheld

This project builds a **custom** Bazzite image for the Zotac Zone gaming handheld with integrated OpenZotacZone drivers, 144 Hz and HDR fixes, improved fan control, and a preinstalled Decky Loader with a curated plugin set.[page:2]

## Why this image?

OpenZotacZone drivers installed via `build.sh` or manual scripts are only temporary and need to be rebuilt and reinstalled after kernel updates.
A custom Bazzite-based image makes these drivers persistent – they survive system updates, reboots, and rebases within the Universal Blue / bootc workflow.

## Based on

- Zotac-specific adjustments: [https://github.com/Reed-Schimmel/ZotacBazzite](https://github.com/Reed-Schimmel/ZotacBazzite)  
- Official Universal Blue image template: [https://github.com/ublue-os/image-template](https://github.com/ublue-os/image-template)

## Disclaimer

This project is provided as-is, without warranty of any kind, express or implied.
Use it at your own risk.
The authors and contributors accept no liability for hardware damage, data loss, failed updates, or any other issues resulting from the use, modification, or redistribution of this image or the included scripts.

## Features

- Integrated OpenZotacZone drivers, baked into the image and automatically loaded on boot.
- Release builds sign the out-of-tree kernel modules for Secure Boot and ship the public MOK certificate for enrollment.
- Zotac Zone–specific functionality:
  - Fully functional back buttons (P4/P3-like).
  - RGB lighting controllable via OpenRGB.
  - Fan curves (EC fan control) managed via CoolerControl.
  - Joystick dials with precise input via rotation and press.
  - Extended HID protocol support.
  - Touchpad tweaks for more precise input.
  - HDR fix scripts for more reliable HDR activation in supported games
  - 144 Hz fixes (X11/Wayland configuration + Gamescope/KWin tuning) so the panel runs consistently at 144 Hz.

## Secure Boot

Release builds on `main` now expect two GitHub Actions secrets:

- `SECUREBOOT_MOK_KEY`: PEM-encoded private key used to sign the kernel modules.
- `SECUREBOOT_MOK_CERT`: Matching PEM-encoded X.509 certificate.

The build passes those secrets only into the artifact-builder stage, decodes them temporarily during module compilation, signs the generated `.ko` files with the kernel `sign-file` helper, and publishes the public certificate inside the image at `/usr/share/secureboot/zotac-zone-mok.der` and `/usr/share/secureboot/zotac-zone-mok.pem`.

To use the signed modules on a Secure Boot system, enroll that certificate with `mokutil` before loading the image's out-of-tree modules. The image also exposes the same certificate at `/etc/pki/akmods/certs/akmods-zotac-zone.der` and ships `/usr/bin/zotac-secureboot-enroll` for a Bazzite-compatible enrollment flow.

That helper follows the same user-facing password convention Bazzite uses and prompts for the one-time MOK password `universalblue`. This enrolls this project's own certificate, not Bazzite's certificate.

Generate a new MOK keypair once:

```bash
mkdir -p secureboot
openssl req \
  -new -x509 \
  -newkey rsa:4096 \
  -keyout secureboot/MOK.priv \
  -out secureboot/MOK.pem \
  -nodes \
  -days 3650 \
  -subj "/CN=Zotac Zone Module Signing/"
openssl x509 -outform DER \
  -in secureboot/MOK.pem \
  -out secureboot/MOK.der
chmod 600 secureboot/MOK.priv
```

Add the PEM files to GitHub Actions secrets for this repository:

```bash
gh secret set SECUREBOOT_MOK_KEY < secureboot/MOK.priv
gh secret set SECUREBOOT_MOK_CERT < secureboot/MOK.pem
```

Default boot-time behavior:

1. If `/usr/share/secureboot/zotac-zone-mok.der` is already enrolled, nothing happens.
2. If Secure Boot is disabled, nothing happens.
3. If the certificate is not enrolled, `zotac-zone-drivers.service` does not load the Zotac modules yet.
4. Run `sudo /usr/bin/zotac-secureboot-enroll`.
5. The helper runs `mokutil --timeout -1` and `mokutil --import /etc/pki/akmods/certs/akmods-zotac-zone.der`.
6. It only reports `Enrollment request queued.` after confirming the certificate appears in `mokutil --list-new`.
7. On the next boot, MokManager appears and you must confirm the enrollment manually.

Queue enrollment manually:

```bash
sudo /usr/bin/zotac-secureboot-enroll
```

The helper prompts you for the one-time MOK password during `mokutil --import`. Use `universalblue` if you want to match the Universal Blue convention.

Manual enrollment stays available if you do not want to use the helper:

```bash
sudo mokutil --timeout -1
sudo mokutil --import /etc/pki/akmods/certs/akmods-zotac-zone.der
```

MokManager still requires manual confirmation on the next boot; this part cannot be fully automated.

After the import is staged, reboot and complete the enrollment in the blue MOK Manager screen:

1. Choose `Enroll MOK`.
2. Confirm the key enrollment.
3. Enter the password you chose during `mokutil --import`. If you followed the helper's convention, that is `universalblue`.
4. Reboot back into the system.

Once enrolled, future images signed with the same keypair will load without disabling Secure Boot.

## GitHub Actions Configuration

No custom GitHub Actions repository variables are required at the moment. The workflows rely on repository secrets and the built-in `GITHUB_TOKEN`.

Required secrets for normal image publishing:

- `SIGNING_SECRET`: Cosign private key used to sign the pushed container image.
- `COSIGN_PASSWORD`: Password protecting the Cosign private key.
- `SECUREBOOT_MOK_KEY`: PEM private key used for kernel module signing.
- `SECUREBOOT_MOK_CERT`: Matching PEM certificate used for kernel module signing.

Optional secrets for the disk-image upload path in `.github/workflows/build-disk.yml`:

- `S3_PROVIDER`
- `S3_ACCESS_KEY_ID`
- `S3_SECRET_ACCESS_KEY`
- `S3_REGION`
- `S3_ENDPOINT`
- `S3_BUCKET_NAME`

Generate the Cosign keypair once:

```bash
COSIGN_PASSWORD='replace-with-a-strong-password'
export COSIGN_PASSWORD
cosign generate-key-pair
unset COSIGN_PASSWORD
```

That creates `cosign.key` and `cosign.pub`. Store the private key and password in GitHub secrets:

```bash
gh secret set SIGNING_SECRET < cosign.key
gh secret set COSIGN_PASSWORD --body 'replace-with-the-same-cosign-password'
```

Generate the Secure Boot signing keypair once:

```bash
mkdir -p secureboot
openssl req \
  -new -x509 \
  -newkey rsa:4096 \
  -keyout secureboot/MOK.priv \
  -out secureboot/MOK.pem \
  -nodes \
  -days 3650 \
  -subj "/CN=Zotac Zone Module Signing/"
openssl x509 -outform DER \
  -in secureboot/MOK.pem \
  -out secureboot/MOK.der
chmod 600 secureboot/MOK.priv
```

Store the Secure Boot signing keypair in GitHub secrets:

```bash
gh secret set SECUREBOOT_MOK_KEY < secureboot/MOK.priv
gh secret set SECUREBOOT_MOK_CERT < secureboot/MOK.pem
```

The S3-related secrets are not generated locally by this repo; they must come from your object-storage provider if you want `build-disk.yml` to upload artifacts automatically.
