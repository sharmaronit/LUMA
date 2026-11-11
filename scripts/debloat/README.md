# Luma TV Debloater

These scripts make your Android TV faster by turning off preinstalled apps that run in the background: ads, telemetry, promos and unused content apps. They can also set **Luma** as your home screen.

- **Reversible.** By default apps are *disabled*, not deleted. Every run saves a backup, and a single command restores everything.
- **Safe by default.** The `safe` tier only touches ads, telemetry and demo apps. Core system packages are on a protected list and are never touched.
- **Detects your device.** Supported: Google TV (Chromecast, Google TV Streamer, Sony/TCL/Hisense), stock Android TV (Mi Box, Nvidia Shield, Amlogic/Rockchip boxes), Xiaomi PatchWall, and Fire TV.

## 1. Prepare the TV

1. Go to **Settings → Device Preferences → About** (on Fire TV: **Settings → My Fire TV → About**). Click **Build** 7 times to unlock Developer options.
2. In **Developer options**, turn on **USB debugging** or **Network debugging** (on Fire TV: **ADB debugging**).
3. Note the TV's IP address. It's under **Settings → Network**.

## 2. Prepare the PC

Install Android **platform-tools** (adb):
- **Windows:** download platform-tools from developer.android.com, unzip it, and add the folder to PATH. Or pass `-AdbPath C:\platform-tools\adb.exe`.
- **macOS:** `brew install android-platform-tools`
- **Linux:** `sudo apt install adb`

## 3. Run it

Always do a dry run first. It shows exactly what would change and changes nothing.

**Windows** (double-click `debloat.bat`, or run from PowerShell):
```powershell
.\debloat.ps1 -Ip 192.168.1.50 -DryRun
.\debloat.ps1 -Ip 192.168.1.50
```

**macOS / Linux:**
```sh
chmod +x debloat.sh
./debloat.sh --ip 192.168.1.50 --dry-run
./debloat.sh --ip 192.168.1.50
```

The first time you connect, the TV shows an **"Allow USB debugging?"** prompt. Accept it.

### Options

| PowerShell | sh | What it does |
|---|---|---|
| `-Ip ADDR` | `--ip ADDR` | Connect over Wi-Fi (port 5555 unless you give one) |
| `-DryRun` | `--dry-run` | Show the plan and change nothing |
| `-Aggressive` | `--aggressive` | Also remove the **aggressive** tier: voice assistant, Chromecast built-in, ambient mode, OEM stores, OTA updaters |
| `-SetLauncher` | `--set-launcher` | Make Luma the default home app |
| `-DisableStockLauncher` | `--disable-stock-launcher` | Disable the stock home screen. Only runs if Luma is installed |
| `-Compile` | `--compile` | Compile Luma ahead of time for a faster cold start |
| `-FastAnimations` | `--fast-animations` | Set system animations to 0.5x so menus feel snappier |
| `-Uninstall` | `--uninstall` | Use `pm uninstall --user 0` instead of disabling (some Fire TVs need this) |
| `-Device NAME` | `--device NAME` | Skip detection: `google-tv`, `android-tv-stock`, `xiaomi-patchwall`, `fire-tv` |
| `-Reboot` | `--reboot` | Reboot when finished |
| `-Yes` | `--yes` | Don't ask for confirmation |
| `-Restore FILE` | `--restore FILE` | Undo a previous run |

**Recommended "make it fast" run:**
```powershell
.\debloat.ps1 -Ip 192.168.1.50 -SetLauncher -Compile -FastAnimations -Reboot
```

## 4. Undo

Each run writes `backups/<model>-<time>.actions`, which lists exactly what was changed, and a full package snapshot. To undo:
```powershell
.\debloat.ps1 -Ip 192.168.1.50 -Restore .\backups\Chromecast_HD-20261111-153000.actions
```
```sh
./debloat.sh --ip 192.168.1.50 --restore backups/Chromecast_HD-20261111-153000.actions
```
A factory reset also restores every app, because nothing is deleted from the system partition.

## Tiers

| Tier | Removed when | Examples |
|---|---|---|
| `safe` | always | Feedback reporters, telemetry, Play Games, Play Movies, ambient-mode ads, Xiaomi analytics, Amazon metrics |
| `aggressive` | `-Aggressive` | Google Assistant / Alexa, Chromecast built-in, YouTube Music, Prime Video, OTA updaters |
| `launcher` | `-DisableStockLauncher` | Google TV home, Android TV home, PatchWall, Fire TV home |
| `never` | never | Play services, Play Store, Settings, keyboard, Bluetooth, TV provider, WebView, Amazon Appstore |

Lists are in `lists/*.txt`. Each line is `tier|package|description`. Packages that aren't installed on your TV are skipped.

## Device notes

- **Google TV:** if `-SetLauncher` doesn't stick after pressing Home, also add `-DisableStockLauncher`.
- **Fire TV (Fire OS 7.6+):** Amazon blocks disabling its launcher without root, so that step reports FAIL, which is harmless. If many packages fail with "cannot change component state", re-run with `-Uninstall`. To open Luma with the Home button, use a button-remapper app.
- **Xiaomi PatchWall:** disabling `com.mitv.tvhome` (the launcher tier) also removes the PatchWall Live TV guide.
- **Disabling OTA updaters** (aggressive tier) stops security updates. Only do this if you understand the trade-off.

## Troubleshooting

- **"No authorised device found"**: accept the prompt on the TV. If it doesn't appear, turn debugging off and on again, then run `adb kill-server`.
- **"More than one device"**: pass `-Ip` / `--ip`.
- **Something broke**: run `-Restore` with the latest `.actions` file, then reboot.
