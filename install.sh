#!/bin/bash
#
# Installer for the keyboard backlight on Clevo laptops (barebone NP50RNA and
# similar) running Ubuntu.
#
# The problem: this laptop's firmware sends the backlight hotkey events over
# WMI/ACPI (GUID ABBC0F6D-... / ACPI device CLV0001), but Ubuntu ships no driver
# for it. As a result Fn + volume up/down does nothing and /sys/class/leds/ has
# no keyboard entry at all.
#
# The fix: install the tuxedo-keyboard kernel module (NovaCustom's fork covering
# all Clevo laptops), which creates the LED /sys/class/leds/rgb:kbd_backlight,
# plus a small daemon to handle the Fn keys.
#
# Also compatible with Clevo rebrands, e.g. the Axioo Pongo 725.
#
# Run:  sudo ./install.sh
#
set -euo pipefail

if [ "$EUID" -ne 0 ]; then
  echo "Must be root. Run:  sudo $0"
  exit 1
fi

HERE="$(cd "$(dirname "$0")" && pwd)"
SRC_DIR="$HERE/clevo-keyboard"
REAL_USER="${SUDO_USER:-$USER}"
KVER="$(uname -r)"
DKMS_NAME="tuxedo-keyboard"
DKMS_VER="3.2.10"
DKMS_SRC="/usr/src/$DKMS_NAME-$DKMS_VER"

# installed file names (prefix "clevo-backlight")
UNIT_MAIN="clevo-backlight.service"
UNIT_DAEMON="kbdlightd.service"
UDEV_RULE="99-clevo-backlight.rules"
MODLOAD="clevo-backlight.conf"

if [ ! -d "$SRC_DIR" ]; then
  echo "ERROR: source folder $SRC_DIR not found."
  echo "Make sure the whole repo folder was copied intact."
  exit 1
fi

echo "==> 0/8 Make sure the files are executable"
chmod +x "$HERE/install.sh" "$HERE/kbdlight" "$HERE/kbdlightd" 2>/dev/null || true

echo "==> 1/8 Clean up an older install (files named 'axioo-*')"
# the first version of this repo used the prefix "axioo-"; remove it to avoid duplicates
for old in axioo-backlight.service; do
  if [ -e "/etc/systemd/system/$old" ]; then
    systemctl disable --now "$old" >/dev/null 2>&1 || true
    rm -f "/etc/systemd/system/$old"
    echo "    removed: /etc/systemd/system/$old"
  fi
done
if [ -e /etc/udev/rules.d/99-axioo-backlight.rules ]; then
  rm -f /etc/udev/rules.d/99-axioo-backlight.rules
  echo "    removed: /etc/udev/rules.d/99-axioo-backlight.rules"
fi
if [ -e /etc/modules-load.d/axioo-backlight.conf ]; then
  rm -f /etc/modules-load.d/axioo-backlight.conf
  echo "    removed: /etc/modules-load.d/axioo-backlight.conf"
fi
systemctl daemon-reload 2>/dev/null || true

echo "==> 2/8 Install dependencies (dkms, build-essential, headers)"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y dkms build-essential "linux-headers-$KVER"

echo "==> 3/8 Unload old module versions (if currently loaded)"
modprobe -r clevo_acpi       2>/dev/null || true
modprobe -r clevo_wmi        2>/dev/null || true
modprobe -r tuxedo_io        2>/dev/null || true
modprobe -r tuxedo_keyboard  2>/dev/null || true

echo "==> 4/8 Register with DKMS (rebuilt automatically on every kernel update)"
if dkms status "$DKMS_NAME" 2>/dev/null | grep -q "$DKMS_NAME"; then
  dkms remove -m "$DKMS_NAME" -v "$DKMS_VER" --all 2>/dev/null || true
fi

# DKMS requires the source to live in /usr/src/<name>-<version>
rm -rf "$DKMS_SRC"
mkdir -p "$DKMS_SRC"
cp -a "$SRC_DIR"/. "$DKMS_SRC"/
make -C "$DKMS_SRC" clean >/dev/null 2>&1 || true

dkms add     -m "$DKMS_NAME" -v "$DKMS_VER"
dkms build   -m "$DKMS_NAME" -v "$DKMS_VER" -k "$KVER"
dkms install -m "$DKMS_NAME" -v "$DKMS_VER" -k "$KVER"

echo "==> 5/8 Load the modules now"
modprobe tuxedo_keyboard
modprobe clevo_wmi
modprobe clevo_acpi

if [ ! -d /sys/class/leds/rgb:kbd_backlight ]; then
  echo
  echo "WARNING: LED rgb:kbd_backlight did not show up."
  echo "Check:  dmesg | grep -iE 'tuxedo|clevo'"
  echo "Continuing anyway; it usually appears after a reboot."
  echo
fi

echo "==> 6/8 Load automatically at boot"
printf 'tuxedo_keyboard\nclevo_wmi\nclevo_acpi\n' > "/etc/modules-load.d/$MODLOAD"

echo "==> 7/8 Let user '$REAL_USER' control the backlight without sudo"
# brightness is owned by root:input -> joining the input group is enough.
# multi_intensity is still root-only -> needs a udev rule.
#
# IMPORTANT: /sys/class/leds/rgb:kbd_backlight is a SYMLINK. "chgrp -R" defaults
# to -P, which does not follow symlinks, so the rule must name the target files
# explicitly (only "-H"/a path through the symlink works).
cat > "/etc/udev/rules.d/$UDEV_RULE" <<'EOF'
# Clevo laptops (NP50RNA and similar) - let the input group control the keyboard backlight
SUBSYSTEM=="leds", KERNEL=="rgb:kbd_backlight", ACTION=="add|change", RUN+="/bin/chgrp -H input /sys/class/leds/rgb:kbd_backlight/brightness /sys/class/leds/rgb:kbd_backlight/multi_intensity", RUN+="/bin/chmod g+w /sys/class/leds/rgb:kbd_backlight/brightness /sys/class/leds/rgb:kbd_backlight/multi_intensity"
EOF
udevadm control --reload-rules 2>/dev/null || true
udevadm trigger --subsystem-match=leds 2>/dev/null || true

# apply it right away (so it works without waiting for udev)
chgrp -H input /sys/class/leds/rgb:kbd_backlight/brightness \
                /sys/class/leds/rgb:kbd_backlight/multi_intensity 2>/dev/null || true
chmod g+w   /sys/class/leds/rgb:kbd_backlight/brightness \
            /sys/class/leds/rgb:kbd_backlight/multi_intensity 2>/dev/null || true

NEED_RELOGIN=0
if ! id -nG "$REAL_USER" | tr ' ' '\n' | grep -qx input; then
  usermod -aG input "$REAL_USER"
  NEED_RELOGIN=1
fi

install -m 755 "$HERE/kbdlight"  /usr/local/bin/kbdlight
install -m 755 "$HERE/kbdlightd" /usr/local/bin/kbdlightd

echo "==> 8/8 Enable services: set the backlight at boot + hotkey daemon"
#
# Important note: the kernel module only REPORTS the Fn+volume up/down keys as
# KEY_KBDILLUMUP/DOWN events; it does not change brightness itself (RGB keyboard).
# So a userspace process is required -> kbdlightd.
#
cat > "/etc/systemd/system/$UNIT_MAIN" <<'EOF'
[Unit]
Description=Set the Clevo keyboard backlight to bright white
After=systemd-modules-load.service
Wants=systemd-modules-load.service

[Service]
Type=oneshot
ExecStartPre=/sbin/modprobe tuxedo_keyboard
ExecStartPre=/sbin/modprobe clevo_wmi
ExecStartPre=/sbin/modprobe clevo_acpi
# wait until the LED really shows up (max 10 seconds)
ExecStartPre=/bin/sh -c 'for i in $(seq 1 20); do [ -e /sys/class/leds/rgb:kbd_backlight/brightness ] && exit 0; sleep 0.5; done; exit 0'
ExecStart=/usr/local/bin/kbdlight on
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

cat > "/etc/systemd/system/$UNIT_DAEMON" <<'EOF'
[Unit]
Description=Hotkey daemon for the Clevo keyboard backlight
After=systemd-modules-load.service
Wants=systemd-modules-load.service

[Service]
Type=simple
ExecStartPre=/sbin/modprobe tuxedo_keyboard
ExecStartPre=/sbin/modprobe clevo_wmi
ExecStartPre=/sbin/modprobe clevo_acpi
ExecStart=/usr/local/bin/kbdlightd
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable "$UNIT_MAIN"
systemctl enable "$UNIT_DAEMON"
# do not abort the installer if one of the services cannot start yet
systemctl restart "$UNIT_MAIN"   || true
systemctl restart "$UNIT_DAEMON" || true

sleep 1
echo
echo "======================================================"
echo " DONE"
echo
echo " Current status:"
printf "   module     : "
if lsmod | grep -q '^tuxedo_keyboard'; then echo "loaded"; else echo "NOT loaded"; fi
printf "   LED        : "
if [ -d /sys/class/leds/rgb:kbd_backlight ]; then
  echo "$(cat /sys/class/leds/rgb:kbd_backlight/brightness 2>/dev/null)/255 (color: $(cat /sys/class/leds/rgb:kbd_backlight/multi_intensity 2>/dev/null))"
else
  echo "missing"
fi
printf "   daemon     : "
systemctl is-active "$UNIT_DAEMON" 2>/dev/null || echo "not active"
echo
echo " Manual control (no sudo needed, after logout/login):"
echo "   kbdlight              turn on fully (white)"
echo "   kbdlight off          turn off"
echo "   kbdlight toggle       on <-> off"
echo "   kbdlight up / down    adjust brightness"
echo "   kbdlight FF0000       red color"
echo "   kbdlight status       show current state"
echo
echo " Tip: bind an OS shortcut to 'kbdlight toggle',"
echo "      e.g. in niri:  Mod+F1 { spawn \"kbdlight\" \"toggle\"; }"
if [ "$NEED_RELOGIN" -eq 1 ]; then
  echo
  echo " >>> LOG OUT and back IN once so control without sudo takes effect. <<<"
fi
echo "======================================================"
