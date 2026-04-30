#!/bin/bash
set -ouex pipefail

echo "=== Configure Zotac Zone Image ==="

KERNEL_VERSION=$(ls /usr/lib/modules/ | grep -v 'debug' | sort -V | tail -n 1)
EC_INSTALL_DIR="/usr/lib/zotac-zone-fan"
DIAL_SCRIPT="/usr/bin/zotac_dial_daemon.py"
CC_DIR="/var/opt/coolercontrol"
SECUREBOOT_CERT="/usr/share/secureboot/zotac-zone-mok.der"
SECUREBOOT_COMPAT_CERT_DIR="/etc/pki/akmods/certs"
SECUREBOOT_COMPAT_CERT="${SECUREBOOT_COMPAT_CERT_DIR}/akmods-zotac-zone.der"
SECUREBOOT_DEFAULT_PASSWORD="universalblue"

rpm-ostree install \
    mokutil \
    python3-evdev

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

cat > "${DIAL_SCRIPT}" << 'PYEOF'
#!/usr/bin/env python3
# Zotac Zone Dial Daemon (OpenZONE - Raw HID)
import os, sys, glob, time, argparse
from evdev import UInput, ecodes as e

parser = argparse.ArgumentParser()
parser.add_argument("--left",  default="volume")
parser.add_argument("--right", default="brightness")
args = parser.parse_args()

VID = "1EE9"
PID = "1590"

ACTIONS = {
    "volume":            {"type": "key",       "up": e.KEY_VOLUMEUP,    "down": e.KEY_VOLUMEDOWN},
    "brightness":        {"type": "backlight", "step": 5},
    "scroll":            {"type": "rel",       "axis": e.REL_WHEEL,     "up": 1,  "down": -1},
    "scroll_inverted":   {"type": "rel",       "axis": e.REL_WHEEL,     "up": -1, "down": 1},
    "arrows_vertical":   {"type": "key",       "up": e.KEY_UP,          "down": e.KEY_DOWN},
    "arrows_horizontal": {"type": "key",       "up": e.KEY_RIGHT,       "down": e.KEY_LEFT},
    "media":             {"type": "key",       "up": e.KEY_NEXTSONG,    "down": e.KEY_PREVIOUSSONG},
    "page_scroll":       {"type": "key",       "up": e.KEY_PAGEUP,      "down": e.KEY_PAGEDOWN},
    "zoom":              {"type": "key",       "up": e.KEY_ZOOMIN,      "down": e.KEY_ZOOMOUT},
}

def find_backlight():
    paths = glob.glob("/sys/class/backlight/*")
    if not paths: return None
    paths.sort(key=lambda x: "amdgpu" not in x)
    return paths[0]

def set_backlight(path, direction, step_pct):
    try:
        max_v = int(open(os.path.join(path, "max_brightness")).read())
        cur_v = int(open(os.path.join(path, "brightness")).read())
        step  = max(1, int(max_v * (step_pct / 100.0)))
        new_v = max(0, min(cur_v + (step if direction == "up" else -step), max_v))
        open(os.path.join(path, "brightness"), "w").write(str(new_v))
    except Exception as ex:
        print(f"Backlight Err: {ex}")

def find_hidraw():
    for p in glob.glob("/sys/class/hidraw/hidraw*"):
        try:
            c = open(os.path.join(p, "device/uevent")).read().upper()
            if f"HID_ID={VID}:{PID}" in c or f"PRODUCT={VID}/{PID}" in c:
                return f"/dev/{os.path.basename(p)}"
        except: continue
    return None

def main():
    print(f"Dial Daemon. Links:{args.left} | Rechts:{args.right}")
    backlight = find_backlight()
    cap = {e.EV_KEY: [], e.EV_REL: [e.REL_WHEEL]}
    for a in ACTIONS.values():
        if a["type"] == "key": cap[e.EV_KEY].extend([a["up"], a["down"]])
        elif a["type"] == "rel": cap[e.EV_REL].append(a["axis"])
    ui = UInput(cap, name="Zotac Zone Virtual Dials")
    while True:
        dev_path = find_hidraw()
        if not dev_path:
            time.sleep(3); continue
        try:
            with open(dev_path, "rb") as f:
                while True:
                    data = f.read(64)
                    if not data or len(data) < 4: break
                    if data[0] != 0x03 or data[3] == 0x00: continue
                    trig = data[3]
                    ac, di = None, None
                    if   trig == 0x10: ac, di = ACTIONS.get(args.left),  "down"
                    elif trig == 0x08: ac, di = ACTIONS.get(args.left),  "up"
                    elif trig == 0x02: ac, di = ACTIONS.get(args.right), "down"
                    elif trig == 0x01: ac, di = ACTIONS.get(args.right), "up"
                    if not ac: continue
                    if   ac["type"] == "backlight" and backlight:
                        set_backlight(backlight, di, ac["step"])
                    elif ac["type"] == "key":
                        ui.write(e.EV_KEY, ac[di], 1); ui.write(e.EV_KEY, ac[di], 0); ui.syn()
                    elif ac["type"] == "rel":
                        ui.write(e.EV_REL, ac["axis"], ac[di]); ui.syn()
        except OSError: time.sleep(2)
        except Exception as err: print(f"Err:{err}"); time.sleep(2)

if __name__ == "__main__":
    main()
PYEOF
chmod +x "${DIAL_SCRIPT}"

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

cat > /usr/bin/zotac-secureboot-enroll << EOF
#!/usr/bin/env bash
set -euo pipefail

CERT="${SECUREBOOT_COMPAT_CERT}"
DEFAULT_PASSWORD="${SECUREBOOT_DEFAULT_PASSWORD}"

log() {
    echo "[zotac-secureboot] \$*"
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

if mokutil --test-key "\${CERT}" >/dev/null 2>&1; then
    log "MOK certificate is already enrolled."
    exit 0
fi

mokutil --timeout -1 || true
log "The next prompt is for a one-time MOK password."
log "Use '\${DEFAULT_PASSWORD}' to match the Universal Blue workflow."
mokutil --import "\${CERT}"
log "Enrollment request queued."
log "Reboot, choose Enroll MOK in MokManager, and enter '\${DEFAULT_PASSWORD}'."
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
