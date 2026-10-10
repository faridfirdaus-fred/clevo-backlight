# clevo-backlight

Nyalakan dan atur **backlight keyboard** laptop **Clevo** (barebone **NP50RNA** dan sejenisnya) di Linux/Ubuntu — untuk keyboard RGB 1 zona.

> Di Ubuntu, tombol backlight keyboard tidak berfungsi karena firmware mengirim event-nya lewat **WMI/ACPI** dan Ubuntu tidak menyediakan drivernya. Repo ini memasang driver yang tepat **plus** sebuah CLI untuk mengendalikannya.

**Kompatibel juga dengan laptop rebrand Clevo** — mis. **Axioo Pongo 725**, serta model lain yang memakai barebone Clevo/TUXEDO dengan keyboard RGB.

---

## Daftar isi

- [Masalahnya](#masalahnya)
- [Kompatibilitas](#kompatibilitas)
- [Solusinya](#solusinya)
- [Instalasi](#instalasi)
- [Pemakaian CLI](#pemakaian-cli)
- [Shortcut keyboard (niri / GNOME / KDE)](#shortcut-keyboard)
- [Cara kerjanya](#cara-kerjanya)
- [Pemecahan masalah](#pemecahan-masalah)
- [Uninstall](#uninstall)
- [Lisensi](#lisensi)

---

## Masalahnya

Di laptop ini, **Fn + 1** (kipas) jalan di OS apa pun karena ditangani langsung oleh chip **EC**. Backlight keyboard tidak demikian:

- Firmware mengirim event hotkey backlight lewat **WMI/ACPI**:
  device ACPI `CLV0001`, GUID `ABBC0F6D-8EA1-11D1-00A0-C90629100000`.
- **Ubuntu tidak menyediakan driver** untuk itu (driver-nya hanya ada di Windows).
- Akibatnya `/sys/class/leds/` **tidak punya entri keyboard** sama sekali, dan tombol Fn-nya tidak melakukan apa-apa.

Cek sendiri:

```bash
ls /sys/class/leds/ | grep -i kbd     # kosong = belum ada driver
```

## Kompatibilitas

Cara ini bekerja pada laptop yang memakai **barebone Clevo** dengan keyboard RGB dan mengirim hotkey backlight lewat WMI/ACPI `CLV0001`.

| Perangkat | Status |
|---|---|
| Clevo NP50RNA | ✅ diuji |
| **Axioo Pongo 725** (rebrand NP50RNA) | ✅ diuji |
| Laptop Clevo/TUXEDO lain dengan keyboard RGB 1 zona | ⚠️ kemungkinan besar jalan — cek dulu `ls /sys/class/leds/ \| grep kbd` setelah modul dimuat |
| Clevo dengan keyboard RGB per-tombol (multi zona) | ❌ belum didukung (repo ini hanya menangani 1 zona) |

Laptop **rebrand Clevo** (Axioo, TUXEDO, Schenker, XMG, System76, dll.) memakai firmware yang sama, jadi kalau LED `rgb:kbd_backlight` muncul setelah driver dimuat, CLI-nya langsung bisa dipakai.

## Solusinya

Tiga lapis, semuanya dipasang otomatis oleh `install.sh`:

| Lapis | Apa | Kenapa |
|---|---|---|
| 1 | Driver kernel **`tuxedo_keyboard`** (+ `clevo_wmi`, `clevo_acpi`) dari fork NovaCustom | Membuat LED `/sys/class/leds/rgb:kbd_backlight` — inilah yang benar-benar menyalakan backlight |
| 2 | Daemon **`kbdlightd`** | Driver hanya *melaporkan* tombol Fn sebagai event; daemon menerjemahkannya menjadi penulisan sysfs |
| 3 | **DKMS** + `modules-load.d` + udev + systemd | Supaya semua tetap jalan setelah reboot dan setelah update kernel |

Driver yang dipakai adalah [wessel-novacustom/clevo-keyboard](https://github.com/wessel-novacustom/clevo-keyboard) (turunan driver TUXEDO, dibuka untuk semua laptop Clevo). Sumbernya disertakan di folder [`clevo-keyboard/`](clevo-keyboard/).

## Instalasi

Butuh Ubuntu/Debian dengan `dkms` dan kernel headers (installer yang memasangnya).

```bash
git clone https://github.com/faridfirdaus-fred/clevo-backlight.git
cd clevo-backlight
sudo ./install.sh
```

Setelah selesai, **logout lalu login sekali** (agar user masuk grup `input` sehingga kontrol tanpa sudo aktif).

Uji cepat:

```bash
kbdlight status     # harus menampilkan brightness 255/255
kbdlight off
kbdlight on
```

## Pemakaian CLI

`kbdlight` dipasang ke `/usr/local/bin/kbdlight`.

```bash
kbdlight                  # nyalakan penuh, putih
kbdlight off              # matikan
kbdlight toggle           # nyala <-> mati   (paling pas untuk shortcut)
kbdlight up               # +64 terang
kbdlight down             # -64 terang
kbdlight up 32            # naikkan dengan langkah khusus
kbdlight level 128        # set terang langsung (0-255)
kbdlight 128              # singkatan dari "level 128"

kbdlight color FF0000     # warna merah (hex)
kbdlight color 0 255 0    # warna hijau (R G B)
kbdlight FF0000           # singkatan dari "color FF0000"
kbdlight "255 128 0"      # singkatan dari "color 255 128 0" (oranye)

kbdlight status           # lihat kondisi sekarang
kbdlight help             # bantuan
```

Warna terakhir disimpan di `~/.cache/kbdlight-color`, jadi `up` / `down` / `toggle` tidak menghapus warna yang sedang dipakai.

Kalau `notify-send` tersedia, setiap perubahan juga memunculkan notifikasi desktop — enak kalau dipanggil dari shortcut.

## Shortcut keyboard

Karena tombol Fn bawaan sering dipakai untuk hal lain (mis. volume), cara paling andal adalah memanggil CLI dari **shortcut OS**. Tidak perlu sudo.

### niri (`~/.config/niri/config.kdl`)

```kdl
binds {
    // Super + F1  -> nyala / mati
    Mod+F1 { spawn "kbdlight" "toggle"; }
    // Super + F2 / F3 -> atur terang
    Mod+F2 { spawn "kbdlight" "up"; }
    Mod+F3 { spawn "kbdlight" "down"; }
}
```

### GNOME

`Settings → Keyboard → Custom Shortcuts → +`, lalu:

| Name | Command | Shortcut |
|---|---|---|
| Backlight toggle | `kbdlight toggle` | `Super+F1` |
| Backlight up | `kbdlight up` | `Super+F2` |
| Backlight down | `kbdlight down` | `Super+F3` |

### KDE Plasma

`System Settings → Shortcuts → Custom → Add Command`, command `kbdlight toggle`, lalu set tombolnya.

### Sway / i3

```conf
bindsym $mod+F1 exec kbdlight toggle
bindsym $mod+F2 exec kbdlight up
bindsym $mod+F3 exec kbdlight down
```

## Cara kerjanya

```
   Fn + volume up/down
          │
          ▼
   firmware (WMI/ACPI, CLV0001)
          │
          ▼
   modul tuxedo_keyboard ──► /sys/class/leds/rgb:kbd_backlight   (hardware)
          │                        ▲
          │ event KEY_KBDILLUMUP   │ tulis brightness
          ▼                        │
   /dev/input/event* ──► kbdlightd ┘
```

Detail yang perlu diketahui:

- LED-nya bernama `rgb:kbd_backlight`. Keyboard ini **1 zona RGB**, dikontrol lewat `multi_intensity` (mis. `255 255 255`) dan `brightness` (0-255).
- Modul kernel **hanya melaporkan** tombol sebagai `KEY_KBDILLUMUP` (230) / `KEY_KBDILLUMDOWN` (229) — ia **tidak** mengubah brightness sendiri. Karena itu perlu `kbdlightd`.
- Kalau Anda memakai **keyd** dengan `[ids] *`, keyd akan meng-*grab* keyboard secara eksklusif (`EVIOCGRAB`) dan meneruskan tombol lewat device **"keyd virtual keyboard"**. Supaya tetap jalan dalam kedua kondisi, `kbdlightd` memantau **kedua** device (TUXEDO Keyboard *dan* keyd virtual keyboard) dengan debounce 80 ms.
- Permission: `brightness` dimiliki `root:input`, sedangkan `multi_intensity` root-only. Installer menambahkan user ke grup `input` **dan** memasang udev rule. Catatan: `/sys/class/leds/rgb:kbd_backlight` adalah *symlink*, sehingga udev rule memakai `chgrp -H` dengan **path file target eksplisit** (`chgrp -R` default tidak mengikuti symlink).

### File yang dipasang

| Path | Isi |
|---|---|
| `/usr/src/tuxedo-keyboard-3.2.10/` | sumber driver untuk DKMS |
| `/usr/local/bin/kbdlight` | CLI |
| `/usr/local/bin/kbdlightd` | daemon |
| `/etc/modules-load.d/clevo-backlight.conf` | muat modul saat boot |
| `/etc/udev/rules.d/99-clevo-backlight.rules` | izin LED untuk grup `input` |
| `/etc/systemd/system/clevo-backlight.service` | set backlight putih saat boot |
| `/etc/systemd/system/kbdlightd.service` | daemon hotkey |

## Pemecahan masalah

```bash
# 1. Modul sudah termuat?
lsmod | grep -E "tuxedo|clevo"

# 2. LED sudah muncul?
ls /sys/class/leds/ | grep kbd

# 3. Muat manual kalau perlu
sudo modprobe tuxedo_keyboard clevo_wmi clevo_acpi

# 4. Driver bicara ke hardware? (harus ada baris "Set Color ...")
sudo dmesg | grep -iE "tuxedo|clevo"

# 5. Daemon memantau device apa?
journalctl -u kbdlightd -n 20
#    harus muncul: "memantau /dev/input/eventXX (TUXEDO Keyboard)"
#                  "memantau /dev/input/eventYY (keyd virtual keyboard)"

# 6. Tekan tombol sambil lihat log
journalctl -u kbdlightd -f
#    harapannya: "tombol 230: brightness 255 -> ..."

# 7. Tidak bisa menulis tanpa sudo?
groups | grep input      # kalau kosong: logout+login, atau `sudo usermod -aG input $USER`
```

Kalau LED tetap tidak muncul setelah reboot, DKMS mungkin gagal build untuk kernel baru:

```bash
dkms status
sudo dkms autoinstall        # bangun ulang untuk kernel yang sedang jalan
```

Kalau Anda pernah memasang versi lama repo ini (nama file `axioo-*`), `install.sh` akan menghapusnya otomatis di langkah 1/8.

## Uninstall

```bash
sudo dkms remove -m tuxedo-keyboard -v 3.2.10 --all
sudo rm -f /etc/modules-load.d/clevo-backlight.conf
sudo rm -f /etc/udev/rules.d/99-clevo-backlight.rules
sudo rm -f /etc/systemd/system/clevo-backlight.service
sudo rm -f /etc/systemd/system/kbdlightd.service
sudo rm -f /usr/local/bin/kbdlight /usr/local/bin/kbdlightd
sudo systemctl daemon-reload
sudo udevadm control --reload-rules
# opsional: keluarkan dari grup input
sudo gpasswd -d "$USER" input
```

## Lisensi

Skrip di repo ini: MIT — lihat [LICENSE](LICENSE).
Driver di folder `clevo-keyboard/`: **GPL-2.0** dari [wessel-novacustom/clevo-keyboard](https://github.com/wessel-novacustom/clevo-keyboard) (wajib, karena modul kernel).
