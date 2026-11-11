# Luma

**Website:** https://sharmaronit.github.io/LUMA · **Download:** [luma.apk](https://github.com/sharmaronit/LUMA/releases/latest/download/luma.apk)

Luma is a clean, fast home screen for Android TV and Google TV, with a built-in cleaner that switches off the ads, tracking and preloaded extras that slow your TV down.

Created by Ronit Sharma. Free and open source (GPL-3.0-or-later).

- **Clean home screen:** your favourite apps, a clock and your notifications. No ads, no recommendations you did not ask for.
- **Clean my TV:** switches off bloatware from the TV itself. Nothing is deleted, and one press undoes it.
- **Depth wallpapers:** on seven mountain scenes a glass clock sits behind the peaks.
- **Profiles:** each person gets their own favourites, wallpaper, theme, clock and font.
- **Made for the remote:** quick settings, a sleep timer, an input switcher, wallpapers and fonts.

## Pick your way to install

| | You need | Best for |
|---|---|---|
| [A. On the TV only](#a-on-the-tv-only) | Just the TV | Most people |
| [B. With a computer](#b-with-a-computer) | A PC or Mac on the same Wi-Fi | TVs where A does not work, and Fire TV |
| [C. With an AI assistant](#c-with-an-ai-assistant) | Claude Code, Codex or similar | Letting an assistant do every step for you |

All three do the same two things: install Luma, and switch off bloatware.

**Works on:** Google TV (Chromecast, Google TV Streamer, Sony, TCL, Hisense), Android TV (Mi Box, Nvidia Shield and similar boxes) and Xiaomi PatchWall TVs. Fire TV is partly supported: the cleaner works with a computer, but recent Fire TVs block other home screens. Luma does not work on Samsung (Tizen), LG (webOS) or Roku.

---

## A. On the TV only

### 1. Install Luma

1. On the TV, open the Play Store and install **Downloader** (by AFTVnews).
2. Open Downloader and allow it to install apps when the TV asks.
3. Enter this address and choose Go:
   `github.com/sharmaronit/LUMA/releases/latest/download/luma.apk`
4. Choose **Install** when the download finishes.
5. Open Luma and follow the short setup. Choose **Luma** when the TV asks which Home app to use.

### 2. Clean your TV

1. Open **Settings > Device Preferences > About** and press OK on **Build** seven times. The TV says you are now a developer.
2. Go back, open **Developer options** and switch on **USB debugging** (some TVs call it Network debugging).
3. In Luma, select the clock, then **Settings > Device > Clean my TV**.
4. The TV asks "Allow USB debugging?". Tick **Always allow from this computer** and choose **Allow**.
5. Luma lists what it can switch off. The recommended items are already ticked. Choose **Clean**.
6. Restart the TV.

**To undo:** open Clean my TV again and choose **Undo earlier cleaning**.

**If Luma says it cannot connect:** your TV only offers paired "Wireless debugging", which the on-TV cleaner does not support yet. Use option B.

When you have finished, you can switch USB debugging off again. Switch it back on if you want to undo the cleaning later.

---

## B. With a computer

The full guide, with every option, is in [scripts/debloat/README.md](scripts/debloat/README.md). The short version:

1. On the TV, switch on USB debugging (steps 1 and 2 of "Clean your TV" above) and note the TV's IP address under **Settings > Network**.
2. On the computer, install Android platform-tools (`adb`) and download this repository.
3. Download the Luma `.apk` from the [latest release](https://github.com/sharmaronit/LUMA/releases/latest) and install it:
   ```
   adb connect 192.168.1.50
   adb install -r luma.apk
   ```
4. Preview what the cleaner would do. This changes nothing:
   - Windows: `.\scripts\debloat\debloat.ps1 -Ip 192.168.1.50 -DryRun`
   - macOS or Linux: `./scripts/debloat/debloat.sh --ip 192.168.1.50 --dry-run`
5. Run it for real and make Luma the home screen:
   - Windows: `.\scripts\debloat\debloat.ps1 -Ip 192.168.1.50 -SetLauncher -Compile -Reboot`
   - macOS or Linux: `./scripts/debloat/debloat.sh --ip 192.168.1.50 --set-launcher --compile --reboot`

Replace `192.168.1.50` with your TV's address. Every run saves a backup file; the script prints the command that restores it.

---

## C. With an AI assistant

1. On the TV, switch on USB debugging (steps 1 and 2 of "Clean your TV" above).
2. On the computer, open Claude Code, Codex or another coding assistant that can run commands.
3. Copy the contents of [PROMPT.md](PROMPT.md) and paste them in.
4. Answer its questions. It shows you the plan before it changes anything.

The assistant uses the same tested lists as options A and B, so it does not guess what is safe to switch off.

---

## Is it safe?

- Luma only **switches apps off**. It never deletes them, and it never touches the system apps your TV needs: settings, the remote, Wi-Fi, Play services and so on.
- Everything Luma switches off can be switched back on from the same screen, or with the restore command of the computer script.
- The lists of what gets switched off are plain text files in [scripts/debloat/lists](scripts/debloat/lists). Anyone can read and check them.
- Luma does not collect data. See [PRIVACY.md](PRIVACY.md).

## Problems

- **The Home button opens the old home screen.** Some TVs lock their own launcher. Use option B with `-DisableStockLauncher` (`--disable-stock-launcher`).
- **An app I use stopped working.** Undo the cleaning, then run it again and untick that item.
- **Something else.** In Luma, open **Settings > About > Report a problem** and send the report with your TV model.

## Licence and credits

Luma is free software under the GNU General Public License, version 3 or later. It includes code from earlier open-source launchers; their notices are in [NOTICE](NOTICE) and in the app under **Settings > About > Licences & credits**.
