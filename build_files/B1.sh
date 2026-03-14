#!/bin/bash
set -ouex pipefail

# ==============================================================================
#  Zotac Zone – Bazzite Custom Image Build Script
#
#  Quellen:
#    Treiber (HID/Platform/Dials): github.com/OpenZotacZone/ZotacZone-Drivers
#    Fan EC-Treiber:               gist.github.com/ElektroCoder (+ Pfahli Installer)
#    HDR & 144hz Fix:              github.com/OpenZotacZone/Zotac-Zone-HDR-144hz
#    Decky Loader + Plugins:       github.com/SteamDeckHomebrew
# ==============================================================================

echo "=== Starte Zotac Zone Build ==="

OPENZONE_RAW="https://raw.githubusercontent.com/OpenZotacZone/ZotacZone-Drivers/refs/heads/main"
ELEKTROCODER_RAW="https://gist.githubusercontent.com/ElektroCoder/c3ddfbe6dff057ab16375ab965876e74/raw/a7bdf061ca0613ef243e1e9851b70e886face4ea"
HDR_RAW="https://raw.githubusercontent.com/OpenZotacZone/Zotac-Zone-HDR-144hz/refs/heads/main"

# ==============================================================================
# 1. ABHÄNGIGKEITEN
# ==============================================================================
echo "-> Installiere Build-Abhängigkeiten..."

KERNEL_VERSION=$(ls /usr/lib/modules/ | grep -v 'debug' | sort -V | tail -n 1)

rpm-ostree install \
    kernel-devel-${KERNEL_VERSION} \
    gcc \
    make \
    wget \
    git \
    python3-pip

pip install evdev --break-system-packages

# ==============================================================================
# 2. OPENZONE HID + PLATFORM TREIBER
#    Quelle: github.com/OpenZotacZone/ZotacZone-Drivers
#    Liefert: Input, Back-Buttons, RGB, Radial-Dials, Platform-Sensor
# ==============================================================================
echo "-> Baue OpenZONE HID & Platform Treiber..."

BUILD_DIR="/tmp/zotac_zone_build"
DRIVER_INSTALL_DIR="/usr/local/lib/zotac-zone"
mkdir -p "$BUILD_DIR" "$DRIVER_INSTALL_DIR"
cd "$BUILD_DIR"

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

make -C /usr/lib/modules/${KERNEL_VERSION}/build M=$(pwd) modules
cp *.ko "$DRIVER_INSTALL_DIR/"

cat > /usr/lib/systemd/system/zotac-zone-drivers.service << EOF
[Unit]
Description=Zotac Zone HID & Platform Drivers (OpenZONE)
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/sbin/modprobe led-class-multicolor
ExecStart=/usr/sbin/modprobe platform_profile
ExecStart=/usr/sbin/insmod ${DRIVER_INSTALL_DIR}/firmware_attributes_class.ko
ExecStart=/usr/sbin/insmod ${DRIVER_INSTALL_DIR}/zotac-zone-platform.ko
ExecStart=/usr/sbin/insmod ${DRIVER_INSTALL_DIR}/zotac-zone-hid.ko
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl enable zotac-zone-drivers.service

cat > /usr/lib/udev/rules.d/99-zotac-zone.rules << 'EOF'
KERNEL=="hidraw*", ATTRS{idVendor}=="1ee9", ATTRS{idProduct}=="1590", MODE="0666"
EOF

echo "uinput" > /usr/lib/modules-load.d/zotac-uinput.conf
