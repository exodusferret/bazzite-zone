#!/bin/bash
set -ouex pipefail

echo "=== Configure Zotac Zone Image ==="

KERNEL_VERSION=$(ls /usr/lib/modules/ | grep -v 'debug' | sort -V | tail -n 1)
EC_INSTALL_DIR="/usr/lib/zotac-zone-fan"
DIAL_SCRIPT="/usr/local/bin/zotac_dial_daemon.py"
OPENZONE_MANAGER_SCRIPT="/usr/local/bin/openzone_manager.sh"
OPENZONE_UNINSTALL_SCRIPT="/usr/local/bin/uninstall_openzone_drivers.sh"
CC_DIR="/var/opt/coolercontrol"
HDR_SCRIPT_SOURCE="/usr/share/gamescope/scripts/00-gamescope/displays/zotac.zone.oled.lua"
HDR_INSTALLER="/usr/bin/zotac-install-gamescope-hdr"
SECUREBOOT_CERT="/usr/share/secureboot/zotac-zone-mok.der"
SECUREBOOT_COMPAT_CERT_DIR="/etc/pki/akmods/certs"
SECUREBOOT_COMPAT_CERT="${SECUREBOOT_COMPAT_CERT_DIR}/akmods-zotac-zone.der"
SECUREBOOT_DEFAULT_PASSWORD="universalblue"
STEAMOS_MANAGER_ETC_DIR="/etc/steamos-manager"
STEAMOS_MANAGER_SHARE_DIR="/usr/share/steamos-manager"
STEAMOS_MANAGER_DEVICES_DIR="${STEAMOS_MANAGER_SHARE_DIR}/devices"
STEAMOS_MANAGER_DEVICE_CONFIG="${STEAMOS_MANAGER_DEVICES_DIR}/zotac-gaming-zone.toml"
STEAMOS_MANAGER_CONFIG="${STEAMOS_MANAGER_ETC_DIR}/config.toml"

rpm-ostree install \
    mokutil \
    python3-evdev

if [[ ! -f "${HDR_SCRIPT_SOURCE}" ]]; then
    echo "Missing expected HDR script artifact: ${HDR_SCRIPT_SOURCE}"
    exit 1
fi

cat > /usr/bin/zotac-load-drivers << EOF
#!/usr/bin/env bash
set -euo pipefail

CERT="${SECUREBOOT_CERT}"

log() {
    echo "[zotac-load-drivers] \$*"
}

if command -v mokutil >/dev/null 2>&1 \
    && [[ -r "\${CERT}" ]] \
    && mokutil --sb-state 2>/dev/null | grep -qi "SecureBoot enabled" \
    && ! mokutil --test-key "\${CERT}" >/dev/null 2>&1; then
    log "Secure Boot is enabled and the Zotac MOK is not enrolled yet."
    log "Run /usr/bin/zotac-secureboot-enroll, reboot, and complete the enrollment in MokManager."
    exit 0
fi

/usr/sbin/modprobe led-class-multicolor
/usr/sbin/modprobe platform_profile
/usr/sbin/modprobe firmware_attributes_class
/usr/sbin/modprobe zotac-zone-platform
/usr/sbin/modprobe zotac-zone-hid
EOF
chmod 700 /usr/bin/zotac-load-drivers

cat > /usr/lib/systemd/system/zotac-zone-drivers.service << EOF
[Unit]
Description=Zotac Zone HID & Platform Drivers (OpenZONE)
After=local-fs.target

[Service]
Type=oneshot
ExecStart=/usr/bin/zotac-load-drivers
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

cat > /usr/lib/udev/rules.d/99-zotac-zone.rules << 'EOF'
KERNEL=="hidraw*", ATTRS{idVendor}=="1ee9", ATTRS{idProduct}=="1590", MODE="0666"
EOF

echo "uinput" > /usr/lib/modules-load.d/zotac-uinput.conf

for required_script in \
    "${DIAL_SCRIPT}" \
    "${OPENZONE_MANAGER_SCRIPT}" \
    "${OPENZONE_UNINSTALL_SCRIPT}"
do
    if [[ ! -x "${required_script}" ]]; then
        echo "Missing expected upstream OpenZotacZone artifact: ${required_script}"
        exit 1
    fi
done

cat > /usr/lib/systemd/system/zotac-dials.service << EOF
[Unit]
Description=Zotac Zone Dial Daemon (OpenZONE)
After=multi-user.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 ${DIAL_SCRIPT} --left volume --right brightness
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

install -d -m 755 "${SECUREBOOT_COMPAT_CERT_DIR}"
ln -sf "${SECUREBOOT_CERT}" "${SECUREBOOT_COMPAT_CERT}"

install -d -m 755 \
    "${STEAMOS_MANAGER_ETC_DIR}" \
    "${STEAMOS_MANAGER_SHARE_DIR}/system.d" \
    "${STEAMOS_MANAGER_DEVICES_DIR}"

if [[ ! -f "${STEAMOS_MANAGER_DEVICE_CONFIG}" ]]; then
    echo "Missing expected steamos-manager device profile: ${STEAMOS_MANAGER_DEVICE_CONFIG}"
    exit 1
fi

ln -sf "${STEAMOS_MANAGER_DEVICE_CONFIG}" "${STEAMOS_MANAGER_CONFIG}"

cat > /usr/bin/zotac-secureboot-enroll << EOF
#!/usr/bin/env bash
set -euo pipefail

CERT="${SECUREBOOT_COMPAT_CERT}"
DEFAULT_PASSWORD="${SECUREBOOT_DEFAULT_PASSWORD}"
HASH_FILE=""

log() {
    echo "[zotac-secureboot] \$*"
}

cleanup() {
    if [[ -n "\${HASH_FILE}" && -f "\${HASH_FILE}" ]]; then
        rm -f "\${HASH_FILE}"
    fi
}

trap cleanup EXIT

cert_fingerprint() {
    openssl x509 -inform DER -in "\$1" -noout -fingerprint | cut -d= -f2
}

fingerprint_in_mok_list() {
    local fingerprint list_output

    fingerprint="\$(printf '%s' "\$1" | tr '[:lower:]' '[:upper:]')"
    list_output="\$2"

    printf '%s\n' "\${list_output}" | tr '[:lower:]' '[:upper:]' | grep -Fq "\${fingerprint}"
}

if [[ ! -r "\${CERT}" ]]; then
    log "No MOK certificate found at \${CERT}; skipping."
    exit 0
fi

if ! command -v mokutil >/dev/null 2>&1; then
    log "mokutil is not installed; skipping."
    exit 0
fi

if ! mokutil --sb-state 2>/dev/null | grep -qi "SecureBoot enabled"; then
    log "Secure Boot is not enabled; no enrollment needed."
    exit 0
fi

CERT_FINGERPRINT="\$(cert_fingerprint "\${CERT}")"
ENROLLED_KEYS="\$(mokutil --list-enrolled 2>/dev/null || true)"

if mokutil --test-key "\${CERT}" >/dev/null 2>&1 \
    || fingerprint_in_mok_list "\${CERT_FINGERPRINT}" "\${ENROLLED_KEYS}"; then
    log "MOK certificate is already enrolled."
    exit 0
fi

mokutil --timeout -1 || true
HASH_FILE="\$(mktemp)"
chmod 600 "\${HASH_FILE}"
mokutil --generate-hash="\${DEFAULT_PASSWORD}" > "\${HASH_FILE}"
log "Using the built-in one-time MOK password convention."
log "Password: '\${DEFAULT_PASSWORD}'"

# Interactive flow kept for reference:
# log "The next prompt is for a one-time MOK password."
# log "Use '\${DEFAULT_PASSWORD}' to match the Universal Blue workflow."
# IMPORT_OUTPUT="\$(mokutil --import "\${CERT}" 2>&1)"

IMPORT_OUTPUT="\$(mokutil --import "\${CERT}" --hash-file "\${HASH_FILE}" 2>&1)"
printf '%s\n' "\${IMPORT_OUTPUT}"

if mokutil --test-key "\${CERT}" >/dev/null 2>&1 \
    || fingerprint_in_mok_list "\${CERT_FINGERPRINT}" "\${ENROLLED_KEYS}"; then
    log "MOK certificate is already enrolled; no new enrollment was queued."
    exit 0
fi

PENDING_KEYS="\$(mokutil --list-new 2>/dev/null || true)"

if fingerprint_in_mok_list "\${CERT_FINGERPRINT}" "\${PENDING_KEYS}"; then
    log "Enrollment request queued."
    log "Reboot, choose Enroll MOK in MokManager, and enter '\${DEFAULT_PASSWORD}'."
else
    log "Import completed, but a pending MOK enrollment could not be confirmed."
    log "Check 'mokutil --list-new' before rebooting."
fi
EOF
chmod 700 /usr/bin/zotac-secureboot-enroll

cat > /usr/bin/zotac-fan-enable.sh << EOF
#!/usr/bin/env bash
set -e
echo "[*] Lade Zotac Zone EC Fan-Treiber..."
if ! /usr/sbin/lsmod | grep -q '^zotac_zone_platform '; then
    /usr/sbin/insmod ${EC_INSTALL_DIR}/zotac-zone-platform.ko || { echo "[!] insmod fehlgeschlagen"; exit 0; }
    echo "[+] Modul geladen."
else
    echo "[+] Modul bereits aktiv."
fi
echo "[*] Starte CoolerControl neu..."
/usr/bin/systemctl restart coolercontrold || true
echo "[+] Fan-Setup abgeschlossen."
EOF
chmod +x /usr/bin/zotac-fan-enable.sh

cat > "${HDR_INSTALLER}" << EOF
#!/usr/bin/env bash
set -euo pipefail

SOURCE="${HDR_SCRIPT_SOURCE}"
TARGET_DIR="\${HOME}/.config/gamescope/scripts/00-gamescope/displays"
TARGET_PATH="\${TARGET_DIR}/zotac.zone.oled.lua"

if [[ ! -f "\${SOURCE}" ]]; then
    echo "[zotac-gamescope-hdr] Missing source file: \${SOURCE}" >&2
    exit 1
fi

install -d -m 755 "\${TARGET_DIR}"

if [[ ! -f "\${TARGET_PATH}" ]] || ! cmp -s "\${SOURCE}" "\${TARGET_PATH}"; then
    install -m 644 "\${SOURCE}" "\${TARGET_PATH}"
fi
EOF
chmod 755 "${HDR_INSTALLER}"

install -d -m 755 /usr/lib/systemd/user
cat > /usr/lib/systemd/user/zotac-gamescope-hdr.service << EOF
[Unit]
Description=Install corrected Gamescope HDR display profile for Zotac Zone
After=default.target

[Service]
Type=oneshot
ExecStart=${HDR_INSTALLER}

[Install]
WantedBy=default.target
EOF

install -d -m 755 /etc/systemd/user/default.target.wants
ln -sf /usr/lib/systemd/user/zotac-gamescope-hdr.service \
    /etc/systemd/user/default.target.wants/zotac-gamescope-hdr.service

cat > /usr/lib/systemd/system/coolercontrold.service << EOF
[Unit]
Description=CoolerControl Daemon (Fan Control) – Offiziell
After=network.target
Wants=network.target
ConditionPathExists=${CC_DIR}/CoolerControlD-x86_64.AppImage

[Service]
Type=simple
User=root
Environment=DISPLAY=:0
ExecStart=${CC_DIR}/CoolerControlD-x86_64.AppImage
Restart=on-failure
RestartSec=5
LimitNOFILE=1024

[Install]
WantedBy=multi-user.target
EOF

cat > /usr/lib/systemd/system/zotac-fan.service << 'EOF'
[Unit]
Description=Zotac Zone EC Fan-Treiber
After=multi-user.target coolercontrold.service

[Service]
Type=oneshot
ExecStart=/usr/bin/zotac-fan-enable.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl enable zotac-zone-drivers.service
systemctl enable zotac-dials.service
systemctl enable coolercontrold.service
systemctl enable zotac-fan.service

# useradd -m -G wheel zotac
# echo "zotac:zotac" | chpasswd

systemctl enable sshd.service
depmod -a "${KERNEL_VERSION}"
