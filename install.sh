#!/bin/bash
#
# Installer backlight keyboard Axioo Pongo 725 (barebone Clevo NP50RNA) di Ubuntu.
#
# Masalah: firmware laptop ini mengirim event hotkey backlight lewat WMI/ACPI
# (GUID ABBC0F6D-... / device ACPI CLV0001), tapi Ubuntu tidak menyediakan
# driver-nya. Akibatnya tombol Fn + volume up/down tidak melakukan apa-apa dan
# /sys/class/leds/ tidak punya entri keyboard sama sekali.
#
# Solusi: pasang modul kernel tuxedo-keyboard (fork NovaCustom untuk semua laptop
# Clevo) yang membuat LED /sys/class/leds/rgb:kbd_backlight, plus daemon kecil
# untuk menangani tombol Fn-nya.
#
# Jalankan:  sudo ./install.sh
#
set -euo pipefail

if [ "$EUID" -ne 0 ]; then
  echo "Harus root. Jalankan:  sudo $0"
  exit 1
fi

HERE="$(cd "$(dirname "$0")" && pwd)"
SRC_DIR="$HERE/clevo-keyboard"
REAL_USER="${SUDO_USER:-$USER}"
KVER="$(uname -r)"
DKMS_NAME="tuxedo-keyboard"
DKMS_VER="3.2.10"
DKMS_SRC="/usr/src/$DKMS_NAME-$DKMS_VER"

if [ ! -d "$SRC_DIR" ]; then
  echo "ERROR: folder sumber $SRC_DIR tidak ditemukan."
  echo "Pastikan seluruh folder ~/axioo-backlight disalin utuh."
  exit 1
fi

echo "==> 0/7 Pastikan file bisa dieksekusi"
chmod +x "$HERE/install.sh" "$HERE/kbdlight" "$HERE/kbdlightd" 2>/dev/null || true

echo "==> 1/7 Install dependensi (dkms, build-essential, headers)"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y dkms build-essential "linux-headers-$KVER"

echo "==> 2/7 Lepas modul versi lama (kalau sedang termuat)"
modprobe -r clevo_acpi       2>/dev/null || true
modprobe -r clevo_wmi        2>/dev/null || true
modprobe -r tuxedo_io        2>/dev/null || true
modprobe -r tuxedo_keyboard  2>/dev/null || true

echo "==> 3/7 Daftarkan ke DKMS (dibangun ulang otomatis tiap update kernel)"
if dkms status "$DKMS_NAME" 2>/dev/null | grep -q "$DKMS_NAME"; then
  dkms remove -m "$DKMS_NAME" -v "$DKMS_VER" --all 2>/dev/null || true
fi

# DKMS mewajibkan source berada di /usr/src/<nama>-<versi>
rm -rf "$DKMS_SRC"
mkdir -p "$DKMS_SRC"
cp -a "$SRC_DIR"/. "$DKMS_SRC"/
make -C "$DKMS_SRC" clean >/dev/null 2>&1 || true

dkms add     -m "$DKMS_NAME" -v "$DKMS_VER"
dkms build   -m "$DKMS_NAME" -v "$DKMS_VER" -k "$KVER"
dkms install -m "$DKMS_NAME" -v "$DKMS_VER" -k "$KVER"

echo "==> 4/7 Muat modul sekarang"
modprobe tuxedo_keyboard
modprobe clevo_wmi
modprobe clevo_acpi

if [ ! -d /sys/class/leds/rgb:kbd_backlight ]; then
  echo
  echo "PERINGATAN: LED rgb:kbd_backlight belum muncul."
  echo "Cek:  dmesg | grep -iE 'tuxedo|clevo'"
  echo "Lanjut saja, biasanya muncul setelah reboot."
  echo
fi

echo "==> 5/7 Muat otomatis saat boot"
printf 'tuxedo_keyboard\nclevo_wmi\nclevo_acpi\n' > /etc/modules-load.d/axioo-backlight.conf

echo "==> 6/7 Izinkan user '$REAL_USER' mengatur backlight tanpa sudo"
# brightness milik root:input -> cukup masuk grup input.
# multi_intensity masih root-only -> perlu udev rule.
#
# PENTING: /sys/class/leds/rgb:kbd_backlight adalah SYMLINK. "chgrp -R" default
# (-P) tidak mengikuti symlink, jadi rule-nya harus menyebut file targetnya
# secara eksplisit (baru "-H"/path lewat symlink yang bekerja).
cat > /etc/udev/rules.d/99-axioo-backlight.rules <<'EOF'
# Axioo Pongo 725 (Clevo NP50RNA) - izinkan grup input atur backlight keyboard
SUBSYSTEM=="leds", KERNEL=="rgb:kbd_backlight", ACTION=="add|change", RUN+="/bin/chgrp -H input /sys/class/leds/rgb:kbd_backlight/brightness /sys/class/leds/rgb:kbd_backlight/multi_intensity", RUN+="/bin/chmod g+w /sys/class/leds/rgb:kbd_backlight/brightness /sys/class/leds/rgb:kbd_backlight/multi_intensity"
EOF
udevadm control --reload-rules 2>/dev/null || true
udevadm trigger --subsystem-match=leds 2>/dev/null || true

# terapkan sekarang juga (agar langsung bisa dipakai tanpa tunggu udev)
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

echo "==> 7/7 Aktifkan service: set backlight saat boot + daemon hotkey"
#
# Catatan penting: modul kernel hanya MELAPORKAN tombol Fn+volume up/down sebagai
# event KEY_KBDILLUMUP/DOWN, tidak mengubah brightness sendiri (keyboard RGB).
# Jadi harus ada proses di userspace -> kbdlightd.
#
cat > /etc/systemd/system/axioo-backlight.service <<'EOF'
[Unit]
Description=Set backlight keyboard Axioo Pongo 725 ke putih terang
After=systemd-modules-load.service
Wants=systemd-modules-load.service

[Service]
Type=oneshot
ExecStartPre=/sbin/modprobe tuxedo_keyboard
ExecStartPre=/sbin/modprobe clevo_wmi
ExecStartPre=/sbin/modprobe clevo_acpi
# tunggu LED benar-benar muncul (maks 10 detik)
ExecStartPre=/bin/sh -c 'for i in $(seq 1 20); do [ -e /sys/class/leds/rgb:kbd_backlight/brightness ] && exit 0; sleep 0.5; done; exit 0'
ExecStart=/usr/local/bin/kbdlight on
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/kbdlightd.service <<'EOF'
[Unit]
Description=Daemon hotkey backlight keyboard Axioo Pongo 725
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
systemctl enable axioo-backlight.service
systemctl enable kbdlightd.service
# jangan hentikan installer kalau salah satu service belum bisa jalan
systemctl restart axioo-backlight.service || true
systemctl restart kbdlightd.service       || true

sleep 1
echo
echo "======================================================"
echo " SELESAI"
echo
echo " Status sekarang:"
printf "   modul      : "
if lsmod | grep -q '^tuxedo_keyboard'; then echo "termuat"; else echo "BELUM termuat"; fi
printf "   LED        : "
if [ -d /sys/class/leds/rgb:kbd_backlight ]; then
  echo "$(cat /sys/class/leds/rgb:kbd_backlight/brightness 2>/dev/null)/255 (warna: $(cat /sys/class/leds/rgb:kbd_backlight/multi_intensity 2>/dev/null))"
else
  echo "tidak ada"
fi
printf "   daemon     : "
systemctl is-active kbdlightd.service 2>/dev/null || echo "tidak aktif"
echo
echo " Kontrol manual (tanpa sudo, setelah logout/login):"
echo "   kbdlight              nyalakan penuh (putih)"
echo "   kbdlight off          matikan"
echo "   kbdlight toggle       nyala <-> mati"
echo "   kbdlight up / down    atur terang"
echo "   kbdlight FF0000       warna merah"
echo "   kbdlight status       lihat kondisi"
echo
echo " Tips: pasang shortcut OS yang memanggil 'kbdlight toggle',"
echo "       mis. di niri:  Mod+F1 { spawn \"kbdlight\" \"toggle\"; }"
if [ "$NEED_RELOGIN" -eq 1 ]; then
  echo
  echo " >>> LOGOUT lalu LOGIN sekali supaya kontrol tanpa sudo aktif. <<<"
fi
echo "======================================================"
