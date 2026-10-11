# clevo-backlight

Turn on and control the **keyboard backlight** on **Clevo** laptops (barebone **NP50RNA** and similar) on Linux/Ubuntu — for single-zone RGB keyboards.

> On Ubuntu the keyboard backlight keys do nothing because the firmware sends their events over **WMI/ACPI** and Ubuntu ships no driver for it. This repo installs the right driver **plus** a CLI to control it.

**Also compatible with Clevo rebrands** — e.g. the **Axioo Pongo 725**, and other models built on a Clevo/TUXEDO barebone with an RGB keyboard.

---

## Table of contents

- [The problem](#the-problem)
- [Compatibility](#compatibility)
- [The fix](#the-fix)
- [Installation](#installation)
- [CLI usage](#cli-usage)
- [Keyboard shortcuts (niri / GNOME / KDE)](#keyboard-shortcuts)
- [How it works](#how-it-works)
- [Troubleshooting](#troubleshooting)
- [Uninstall](#uninstall)
- [License](#license)

---

## The problem

On this laptop, **Fn + 1** (fan) works under any OS because it is handled directly by the **EC** chip. The keyboard backlight is different:

- The firmware sends the backlight hotkey events over **WMI/ACPI**:
  ACPI device `CLV0001`, GUID `ABBC0F6D-8EA1-11D1-00A0-C90629100000`.
- **Ubuntu ships no driver** for it (the driver only exists on Windows).
- As a result `/sys/class/leds/` has **no keyboard entry at all**, and the Fn keys do nothing.

Check for yourself:

```bash
ls /sys/class/leds/ | grep -i kbd     # empty = no driver yet
```

## Compatibility

This works on laptops built on a **Clevo barebone** with an RGB keyboard that sends the backlight hotkey over WMI/ACPI `CLV0001`.

| Device | Status |
|---|---|
| Clevo NP50RNA | ✅ tested |
| **Axioo Pongo 725** (rebranded NP50RNA) | ✅ tested |
| Other Clevo/TUXEDO laptops with a single-zone RGB keyboard | ⚠️ very likely works — check `ls /sys/class/leds/ \| grep kbd` after loading the module |
| Clevo with per-key (multi-zone) RGB | ❌ not supported yet (this repo only handles a single zone) |

**Clevo rebrands** (Axioo, TUXEDO, Schenker, XMG, System76, etc.) use the same firmware, so if the `rgb:kbd_backlight` LED appears after the driver loads, the CLI works right away.

## The fix

Three layers, all installed automatically by `install.sh`:

| Layer | What | Why |
|---|---|---|
| 1 | Kernel module **`tuxedo_keyboard`** (+ `clevo_wmi`, `clevo_acpi`) from NovaCustom's fork | Creates the LED `/sys/class/leds/rgb:kbd_backlight` — this is what actually lights up the backlight |
| 2 | Daemon **`kbdlightd`** | The driver only *reports* the Fn keys as events; the daemon turns them into sysfs writes |
| 3 | **DKMS** + `modules-load.d` + udev + systemd | So everything keeps working across reboots and kernel updates |

The driver used is [wessel-novacustom/clevo-keyboard](https://github.com/wessel-novacustom/clevo-keyboard) (a fork of the TUXEDO driver, opened up for all Clevo laptops). Its source is bundled in [`clevo-keyboard/`](clevo-keyboard/).

## Installation

Requires Ubuntu/Debian with `dkms` and kernel headers (the installer takes care of those).

```bash
git clone https://github.com/faridfirdaus-fred/clevo-backlight.git
cd clevo-backlight
sudo ./install.sh
```

When it finishes, **log out and back in once** (so your user joins the `input` group, which enables control without sudo).

Quick test:

```bash
kbdlight status     # should show brightness 255/255
kbdlight off
kbdlight on
```

## CLI usage

`kbdlight` is installed to `/usr/local/bin/kbdlight`.

```bash
kbdlight                  # turn on fully, white
kbdlight off              # turn off
kbdlight toggle           # on <-> off   (best for a shortcut)
kbdlight up               # +64 brightness
kbdlight down             # -64 brightness
kbdlight up 32            # increase by a custom step
kbdlight level 128        # set brightness directly (0-255)
kbdlight 128              # shorthand for "level 128"

kbdlight color FF0000     # red (hex)
kbdlight color 0 255 0    # green (R G B)
kbdlight FF0000           # shorthand for "color FF0000"
kbdlight "255 128 0"      # shorthand for "color 255 128 0" (orange)

kbdlight status           # show the current state
kbdlight help             # help
```

The last color is stored in `~/.cache/kbdlight-color`, so `up` / `down` / `toggle` do not wipe the color currently in use.

If `notify-send` is available, every change also shows a desktop notification — handy when called from a shortcut.

## Keyboard shortcuts

Since the built-in Fn keys are often taken by something else (e.g. volume), the most reliable approach is to call the CLI from an **OS shortcut**. No sudo needed.

### niri (`~/.config/niri/config.kdl`)

```kdl
binds {
    // Super + F1  -> on / off
    Mod+F1 { spawn "kbdlight" "toggle"; }
    // Super + F2 / F3 -> adjust brightness
    Mod+F2 { spawn "kbdlight" "up"; }
    Mod+F3 { spawn "kbdlight" "down"; }
}
```

### GNOME

`Settings → Keyboard → Custom Shortcuts → +`, then:

| Name | Command | Shortcut |
|---|---|---|
| Backlight toggle | `kbdlight toggle` | `Super+F1` |
| Backlight up | `kbdlight up` | `Super+F2` |
| Backlight down | `kbdlight down` | `Super+F3` |

### KDE Plasma

`System Settings → Shortcuts → Custom → Add Command`, command `kbdlight toggle`, then assign the key.

### Sway / i3

```conf
bindsym $mod+F1 exec kbdlight toggle
bindsym $mod+F2 exec kbdlight up
bindsym $mod+F3 exec kbdlight down
```

## How it works

```
   Fn + volume up/down
          │
          ▼
   firmware (WMI/ACPI, CLV0001)
          │
          ▼
   tuxedo_keyboard module ──► /sys/class/leds/rgb:kbd_backlight   (hardware)
          │                        ▲
          │ event KEY_KBDILLUMUP   │ write brightness
          ▼                        │
   /dev/input/event* ──► kbdlightd ┘
```

Details worth knowing:

- The LED is named `rgb:kbd_backlight`. This keyboard is **single-zone RGB**, controlled through `multi_intensity` (e.g. `255 255 255`) and `brightness` (0-255).
- The kernel module **only reports** the keys as `KEY_KBDILLUMUP` (230) / `KEY_KBDILLUMDOWN` (229) — it does **not** change brightness itself. That is why `kbdlightd` is needed.
- If you use **keyd** with `[ids] *`, keyd will grab the keyboard exclusively (`EVIOCGRAB`) and forward its keys through the **"keyd virtual keyboard"** device. To keep working in both cases, `kbdlightd` watches **both** devices (TUXEDO Keyboard *and* keyd virtual keyboard) with an 80 ms debounce.
- Permissions: `brightness` is owned by `root:input`, while `multi_intensity` is root-only. The installer adds your user to the `input` group **and** installs a udev rule. Note: `/sys/class/leds/rgb:kbd_backlight` is a *symlink*, so the udev rule uses `chgrp -H` with **explicit target paths** (`chgrp -R` defaults to not following symlinks).

### Installed files

| Path | Contents |
|---|---|
| `/usr/src/tuxedo-keyboard-3.2.10/` | driver source for DKMS |
| `/usr/local/bin/kbdlight` | CLI |
| `/usr/local/bin/kbdlightd` | daemon |
| `/etc/modules-load.d/clevo-backlight.conf` | load modules at boot |
| `/etc/udev/rules.d/99-clevo-backlight.rules` | LED permissions for the `input` group |
| `/etc/systemd/system/clevo-backlight.service` | set white backlight at boot |
| `/etc/systemd/system/kbdlightd.service` | hotkey daemon |

## Troubleshooting

```bash
# 1. Is the module loaded?
lsmod | grep -E "tuxedo|clevo"

# 2. Did the LED appear?
ls /sys/class/leds/ | grep kbd

# 3. Load it manually if needed
sudo modprobe tuxedo_keyboard clevo_wmi clevo_acpi

# 4. Is the driver talking to the hardware? (expect a "Set Color ..." line)
sudo dmesg | grep -iE "tuxedo|clevo"

# 5. Which devices is the daemon watching?
journalctl -u kbdlightd -n 20
#    expect: "watching /dev/input/eventXX (TUXEDO Keyboard)"
#            "watching /dev/input/eventYY (keyd virtual keyboard)"

# 6. Press a key while watching the log
journalctl -u kbdlightd -f
#    expect: "key 230: brightness 255 -> ..."

# 7. Cannot write without sudo?
groups | grep input      # if empty: log out/in, or `sudo usermod -aG input $USER`
```

If the LED still does not appear after a reboot, DKMS may have failed to build for the new kernel:

```bash
dkms status
sudo dkms autoinstall        # rebuild for the running kernel
```

If you installed an older version of this repo (files named `axioo-*`), `install.sh` removes them automatically in step 1/8.

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
# optional: remove yourself from the input group
sudo gpasswd -d "$USER" input
```

## License

Scripts in this repo: MIT — see [LICENSE](LICENSE).
The driver in `clevo-keyboard/`: **GPL-3.0**, from [wessel-novacustom/clevo-keyboard](https://github.com/wessel-novacustom/clevo-keyboard) (required, since it is a kernel module).
