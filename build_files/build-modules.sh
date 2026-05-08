#!/bin/bash
set -ouex pipefail

echo "=== Build Zotac Zone Artifacts ==="

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
VENDOR_ROOT="${VENDOR_ROOT:-${REPO_ROOT}/vendor}"
OPENZOTAC_REPO_URL="https://github.com/OpenZotacZone/ZotacZone-Drivers.git"
OPENZOTAC_REPO_DIR="${VENDOR_ROOT}/OpenZotacZone"
ELEKTROCODER_REPO_URL="https://gist.github.com/ElektroCoder/c3ddfbe6dff057ab16375ab965876e74.git"
ELEKTROCODER_REPO_DIR="${VENDOR_ROOT}/ElektroCoder-zotac-zone-platform"
OPENZOTAC_REV="${OPENZOTAC_REV:-unknown}"
ELEKTROCODER_REV="${ELEKTROCODER_REV:-unknown}"

source "${SCRIPT_DIR}/dependencies.env"

KERNEL_VERSION=$(ls /usr/lib/modules/ | grep -v 'debug' | sort -V | tail -n 1)
ARTIFACT_ROOT="/artifacts"
OPENZONE_BUILD_DIR="/tmp/zotac_zone_build"
EC_BUILD_DIR="/tmp/zotac_ec_fan_build"
OPENZOTAC_SOURCE_BUNDLE_DIR="/tmp/openzotaczone-corresponding-source"
OPENZONE_OUT="${ARTIFACT_ROOT}/usr/lib/modules/${KERNEL_VERSION}/extra/zotac-zone"
OPENZONE_BIN_OUT="${ARTIFACT_ROOT}/usr/local/bin"
OPENZONE_LIB_OUT="${ARTIFACT_ROOT}/usr/local/lib/zotac-zone"
EC_OUT="${ARTIFACT_ROOT}/usr/lib/zotac-zone-fan"
CC_DIR="${ARTIFACT_ROOT}/var/opt/coolercontrol"
SECUREBOOT_OUT="${ARTIFACT_ROOT}/usr/share/secureboot"
LICENSES_OUT="${ARTIFACT_ROOT}/usr/share/licenses/bazzite-zone"
DOC_OUT="${ARTIFACT_ROOT}/usr/share/doc/bazzite-zone"
GAMESCOPE_DISPLAY_OUT="${ARTIFACT_ROOT}/usr/share/gamescope/scripts/00-gamescope/displays"
SECUREBOOT_TMP_DIR="/tmp/secureboot"
SECUREBOOT_KEY_PATH="${SECUREBOOT_TMP_DIR}/MOK.priv"
SECUREBOOT_CERT_PATH="${SECUREBOOT_TMP_DIR}/MOK.pem"
SECUREBOOT_MOK_KEY_B64="${SECUREBOOT_MOK_KEY_B64:-}"
SECUREBOOT_MOK_CERT_B64="${SECUREBOOT_MOK_CERT_B64:-}"
SIGN_FILE="/usr/lib/modules/${KERNEL_VERSION}/build/scripts/sign-file"
HDR_LUA_URL="https://github.com/ValveSoftware/gamescope/raw/513c8dd65f86e884940b3164c270a20d5b59af4c/scripts/00-gamescope/displays/zotac.zone.oled.lua"
HDR_LUA_NAME="zotac.zone.oled.lua"

mkdir -p \
    "${OPENZONE_OUT}" \
    "${OPENZONE_BIN_OUT}" \
    "${OPENZONE_LIB_OUT}" \
    "${EC_OUT}" \
    "${CC_DIR}" \
    "${SECUREBOOT_OUT}" \
    "${LICENSES_OUT}" \
    "${DOC_OUT}" \
    "${GAMESCOPE_DISPLAY_OUT}" \
    "${SECUREBOOT_TMP_DIR}"

dnf5 -y install --setopt=install_weak_deps=False \
    kernel-devel-${KERNEL_VERSION} \
    gcc \
    make \
    openssl

if [[ -n "${SECUREBOOT_MOK_KEY_B64}" && -n "${SECUREBOOT_MOK_CERT_B64}" ]]; then
    printf '%s' "${SECUREBOOT_MOK_KEY_B64}" | base64 -d > "${SECUREBOOT_KEY_PATH}"
    printf '%s' "${SECUREBOOT_MOK_CERT_B64}" | base64 -d > "${SECUREBOOT_CERT_PATH}"
fi

require_vendor_checkout() {
    local path="$1"
    local name="$2"
    shift 2

    if [[ ! -d "${path}" ]]; then
        echo "Missing vendored dependency checkout at ${path} (${name})."
        echo "Run: git submodule update --init --recursive"
        exit 1
    fi

    for required_path in "$@"; do
        if [[ ! -e "${path}/${required_path}" ]]; then
            echo "Vendored dependency ${name} is missing ${required_path}."
            echo "Run: git submodule update --init --recursive"
            exit 1
        fi
    done
}

extract_upstream_dial_daemon() {
    local installer_script="$1"
    local output_path="$2"

    awk '
        index($0, "cat << '\''EOF'\'' > \"$DIAL_INSTALL_DIR/$DIAL_SCRIPT_NAME\"") {
            capture = 1
            next
        }
        capture && /^EOF$/ {
            exit
        }
        capture {
            print
        }
    ' "${installer_script}" > "${output_path}"

    if [[ ! -s "${output_path}" ]]; then
        echo "Failed to extract zotac_dial_daemon.py from upstream installer."
        exit 1
    fi

    chmod 755 "${output_path}"
}

patch_openzotac_scripts() {
    local manager_script="$1"
    local uninstall_script="$2"

    sed -i \
        's|^DIAL_SERVICE_PATH=.*$|DIAL_SERVICE_PATH="/usr/lib/systemd/system/$DIAL_SERVICE_NAME"|' \
        "${manager_script}"

    sed -i \
        -e 's|/etc/systemd/system/zotac-dials.service|/usr/lib/systemd/system/zotac-dials.service|g' \
        -e 's|/etc/systemd/system/zotac-zone-drivers.service|/usr/lib/systemd/system/zotac-zone-drivers.service|g' \
        "${uninstall_script}"
}

create_openzotac_source_bundle() {
    local resolved_sha="$1"

    rm -rf "${OPENZOTAC_SOURCE_BUNDLE_DIR}"
    mkdir -p "${OPENZOTAC_SOURCE_BUNDLE_DIR}"

    tar \
        --exclude='.git' \
        -C "${OPENZOTAC_REPO_DIR}" \
        -cf - \
        . \
        | tar -C "${OPENZOTAC_SOURCE_BUNDLE_DIR}" -xf -

    cp "${OPENZONE_BIN_OUT}/openzone_manager.sh" \
        "${OPENZOTAC_SOURCE_BUNDLE_DIR}/openzone_manager.sh"
    cp "${OPENZONE_BIN_OUT}/uninstall_openzone_drivers.sh" \
        "${OPENZOTAC_SOURCE_BUNDLE_DIR}/uninstall_openzone_drivers.sh"
    cp "${OPENZONE_BIN_OUT}/zotac_dial_daemon.py" \
        "${OPENZOTAC_SOURCE_BUNDLE_DIR}/zotac_dial_daemon.py"

    cat > "${OPENZOTAC_SOURCE_BUNDLE_DIR}/BUILD-PATCHES.md" <<EOF
# OpenZotacZone Corresponding Source

This bundle corresponds to the OpenZotacZone GPL components redistributed by
bazzite-zone.

- Upstream repository: ${OPENZOTAC_REPO_URL}
- Upstream commit: ${resolved_sha}
- Local packaging changes:
  - \`openzone_manager.sh\`: \`DIAL_SERVICE_PATH\` adjusted to use \`/usr/lib/systemd/system\`
  - \`uninstall_openzone_drivers.sh\`: service removal paths adjusted to use \`/usr/lib/systemd/system\`
  - \`zotac_dial_daemon.py\`: extracted from \`install_openzone_drivers.sh\` and installed as a standalone script
EOF

    tar -C /tmp -czf "${DOC_OUT}/openzotaczone-corresponding-source.tar.gz" \
        "$(basename "${OPENZOTAC_SOURCE_BUNDLE_DIR}")"
}

sign_modules() {
    local module_dir="$1"
    local module

    if [[ ! -s "${SECUREBOOT_KEY_PATH}" || ! -s "${SECUREBOOT_CERT_PATH}" ]]; then
        echo "Secure Boot signing inputs are empty; leaving modules unsigned."
        return 0
    fi

    if [[ ! -x "${SIGN_FILE}" ]]; then
        echo "Missing kernel sign-file helper at ${SIGN_FILE}."
        exit 1
    fi

    shopt -s nullglob
    for module in "${module_dir}"/*.ko; do
        "${SIGN_FILE}" sha256 "${SECUREBOOT_KEY_PATH}" "${SECUREBOOT_CERT_PATH}" "${module}"
    done
    shopt -u nullglob
}

fetch_hdr_display_script() {
    local output_path="${GAMESCOPE_DISPLAY_OUT}/${HDR_LUA_NAME}"

    curl -fL -o "${output_path}" "${HDR_LUA_URL}"
    sed -i \
        's/x = 0.3095, y = 0.3095/x = 0.3070, y = 0.3235/' \
        "${output_path}"
}

require_vendor_checkout \
    "${OPENZOTAC_REPO_DIR}" \
    "OpenZotacZone/ZotacZone-Drivers" \
    "install_openzone_drivers.sh" \
    "openzone_manager.sh" \
    "uninstall_openzone_drivers.sh" \
    "driver/hid" \
    "driver/platform"
require_vendor_checkout \
    "${ELEKTROCODER_REPO_DIR}" \
    "ElektroCoder Zotac platform gist" \
    "zotac-zone-platform.c"
OPENZOTAC_RESOLVED_SHA="${OPENZOTAC_REV}"
ELEKTROCODER_RESOLVED_SHA="${ELEKTROCODER_REV}"

install -m 755 \
    "${OPENZOTAC_REPO_DIR}/openzone_manager.sh" \
    "${OPENZONE_BIN_OUT}/openzone_manager.sh"
install -m 755 \
    "${OPENZOTAC_REPO_DIR}/uninstall_openzone_drivers.sh" \
    "${OPENZONE_BIN_OUT}/uninstall_openzone_drivers.sh"
extract_upstream_dial_daemon \
    "${OPENZOTAC_REPO_DIR}/install_openzone_drivers.sh" \
    "${OPENZONE_BIN_OUT}/zotac_dial_daemon.py"
patch_openzotac_scripts \
    "${OPENZONE_BIN_OUT}/openzone_manager.sh" \
    "${OPENZONE_BIN_OUT}/uninstall_openzone_drivers.sh"

install -m 644 \
    "${OPENZOTAC_REPO_DIR}/LICENSE" \
    "${LICENSES_OUT}/OpenZotacZone-GPL-3.0.txt"

cat > "${DOC_OUT}/openzotaczone-source-info.txt" <<EOF
OpenZotacZone repository: ${OPENZOTAC_REPO_URL}
OpenZotacZone commit: ${OPENZOTAC_RESOLVED_SHA}
Redistributed GPL components:
- /usr/local/bin/openzone_manager.sh
- /usr/local/bin/uninstall_openzone_drivers.sh
- /usr/local/bin/zotac_dial_daemon.py
- /usr/local/lib/zotac-zone/*.ko
- /usr/lib/modules/${KERNEL_VERSION}/extra/zotac-zone/*.ko

The corresponding source for these components is shipped at:
/usr/share/doc/bazzite-zone/openzotaczone-corresponding-source.tar.gz
EOF

create_openzotac_source_bundle "${OPENZOTAC_RESOLVED_SHA}"

cat > "${DOC_OUT}/elektrocoder-source-info.txt" <<EOF
ElektroCoder repository: ${ELEKTROCODER_REPO_URL}
ElektroCoder commit: ${ELEKTROCODER_RESOLVED_SHA}
Redistributed source:
- /usr/lib/zotac-zone-fan/zotac-zone-platform.ko
- source built from vendor/ElektroCoder-zotac-zone-platform/zotac-zone-platform.c
EOF

rm -rf "${OPENZONE_BUILD_DIR}"
mkdir -p "${OPENZONE_BUILD_DIR}"
cp -a "${OPENZOTAC_REPO_DIR}/driver/hid/." "${OPENZONE_BUILD_DIR}/"
cp -a "${OPENZOTAC_REPO_DIR}/driver/platform/." "${OPENZONE_BUILD_DIR}/"

cd "${OPENZONE_BUILD_DIR}"

make -C /usr/lib/modules/${KERNEL_VERSION}/build M="$(pwd)" modules
cp *.ko "${OPENZONE_OUT}/"
cp *.ko "${OPENZONE_LIB_OUT}/"
sign_modules "${OPENZONE_OUT}"
sign_modules "${OPENZONE_LIB_OUT}"

mkdir -p "${EC_BUILD_DIR}"
cd "${EC_BUILD_DIR}"

install -m 644 \
    "${ELEKTROCODER_REPO_DIR}/zotac-zone-platform.c" \
    zotac-zone-platform.c

cat > Makefile << 'EOF'
obj-m += zotac-zone-platform.o
all:
	make -C /lib/modules/$(shell uname -r)/build M=$(PWD) modules
clean:
	make -C /lib/modules/$(shell uname -r)/build M=$(PWD) clean
EOF

make -C /usr/lib/modules/${KERNEL_VERSION}/build M="$(pwd)" modules
cp zotac-zone-platform.ko "${EC_OUT}/"
sign_modules "${EC_OUT}"

if [[ -n "${SECUREBOOT_CERT_PATH}" && -s "${SECUREBOOT_CERT_PATH}" ]]; then
    cp "${SECUREBOOT_CERT_PATH}" "${SECUREBOOT_OUT}/zotac-zone-mok.pem"
    openssl x509 -outform DER \
        -in "${SECUREBOOT_CERT_PATH}" \
        -out "${SECUREBOOT_OUT}/zotac-zone-mok.der"
fi

CC_DOWNLOAD_URL="https://gitlab.com/coolercontrol/coolercontrol/-/releases/${COOLERCONTROL_VERSION}/downloads/packages/CoolerControlD-x86_64.AppImage"

curl -fL -o "${CC_DIR}/CoolerControlD-x86_64.AppImage" "${CC_DOWNLOAD_URL}"
chmod +x "${CC_DIR}/CoolerControlD-x86_64.AppImage"

fetch_hdr_display_script

dnf5 clean all
rm -rf \
    "${OPENZONE_BUILD_DIR}" \
    "${EC_BUILD_DIR}" \
    "${OPENZOTAC_SOURCE_BUNDLE_DIR}" \
    "${SECUREBOOT_TMP_DIR}"
