#!/bin/bash
set -ouex pipefail

echo "=== Build Zotac Zone Artifacts ==="

OPENZONE_RAW="https://raw.githubusercontent.com/OpenZotacZone/ZotacZone-Drivers/refs/heads/main"
ELEKTROCODER_RAW="https://gist.githubusercontent.com/ElektroCoder/c3ddfbe6dff057ab16375ab965876e74/raw/a7bdf061ca0613ef243e1e9851b70e886face4ea"

KERNEL_VERSION=$(ls /usr/lib/modules/ | grep -v 'debug' | sort -V | tail -n 1)
ARTIFACT_ROOT="/artifacts"
OPENZONE_BUILD_DIR="/tmp/zotac_zone_build"
EC_BUILD_DIR="/tmp/zotac_ec_fan_build"
OPENZONE_OUT="${ARTIFACT_ROOT}/usr/lib/modules/${KERNEL_VERSION}/extra/zotac-zone"
EC_OUT="${ARTIFACT_ROOT}/usr/lib/zotac-zone-fan"
CC_DIR="${ARTIFACT_ROOT}/var/opt/coolercontrol"
SECUREBOOT_OUT="${ARTIFACT_ROOT}/usr/share/secureboot"
SECUREBOOT_TMP_DIR="/tmp/secureboot"
SECUREBOOT_KEY_PATH="${SECUREBOOT_TMP_DIR}/MOK.priv"
SECUREBOOT_CERT_PATH="${SECUREBOOT_TMP_DIR}/MOK.pem"
SECUREBOOT_MOK_KEY_B64="${SECUREBOOT_MOK_KEY_B64:-}"
SECUREBOOT_MOK_CERT_B64="${SECUREBOOT_MOK_CERT_B64:-}"
SIGN_FILE="/usr/lib/modules/${KERNEL_VERSION}/build/scripts/sign-file"

mkdir -p "${OPENZONE_OUT}" "${EC_OUT}" "${CC_DIR}" "${SECUREBOOT_OUT}" "${SECUREBOOT_TMP_DIR}"

dnf5 -y install --setopt=install_weak_deps=False \
    kernel-devel-${KERNEL_VERSION} \
    gcc \
    make \
    openssl \
    wget \
    git

if [[ -n "${SECUREBOOT_MOK_KEY_B64}" && -n "${SECUREBOOT_MOK_CERT_B64}" ]]; then
    printf '%s' "${SECUREBOOT_MOK_KEY_B64}" | base64 -d > "${SECUREBOOT_KEY_PATH}"
    printf '%s' "${SECUREBOOT_MOK_CERT_B64}" | base64 -d > "${SECUREBOOT_CERT_PATH}"
fi

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

    for module in "${module_dir}"/*.ko; do
        "${SIGN_FILE}" sha256 "${SECUREBOOT_KEY_PATH}" "${SECUREBOOT_CERT_PATH}" "${module}"
    done
}

mkdir -p "${OPENZONE_BUILD_DIR}"
cd "${OPENZONE_BUILD_DIR}"

for f in \
    "zotac-zone-hid-core.c" \
    "zotac-zone-hid-rgb.c" \
    "zotac-zone-hid-input.c" \
    "zotac-zone-hid-config.c" \
    "zotac-zone.h"
do
    wget -q "${OPENZONE_RAW}/driver/hid/${f}"
done

for f in \
    "zotac-zone-platform.c" \
    "firmware_attributes_class.h" \
    "firmware_attributes_class.c"
do
    wget -q "${OPENZONE_RAW}/driver/platform/${f}"
done

cat > Makefile << 'EOF'
obj-m += zotac-zone-hid.o
zotac-zone-hid-y := zotac-zone-hid-core.o zotac-zone-hid-rgb.o zotac-zone-hid-input.o zotac-zone-hid-config.o
obj-m += firmware_attributes_class.o
obj-m += zotac-zone-platform.o
all:
	make -C /lib/modules/$(shell uname -r)/build M=$(PWD) modules
clean:
	make -C /lib/modules/$(shell uname -r)/build M=$(PWD) clean
EOF

make -C /usr/lib/modules/${KERNEL_VERSION}/build M="$(pwd)" modules
cp *.ko "${OPENZONE_OUT}/"
sign_modules "${OPENZONE_OUT}"

mkdir -p "${EC_BUILD_DIR}"
cd "${EC_BUILD_DIR}"

wget -q -O zotac-zone-platform.c \
    "${ELEKTROCODER_RAW}/zotac-zone-platform.c"

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

COOLERCONTROL_VERSION="4.0.1"
CC_DOWNLOAD_URL="https://gitlab.com/coolercontrol/coolercontrol/-/releases/${COOLERCONTROL_VERSION}/downloads/packages/CoolerControlD-x86_64.AppImage"

curl -fL -o "${CC_DIR}/CoolerControlD-x86_64.AppImage" "${CC_DOWNLOAD_URL}"
chmod +x "${CC_DIR}/CoolerControlD-x86_64.AppImage"

dnf5 clean all
rm -rf "${OPENZONE_BUILD_DIR}" "${EC_BUILD_DIR}" "${SECUREBOOT_TMP_DIR}"
