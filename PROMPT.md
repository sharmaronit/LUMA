# Clean my TV and install Luma

Paste everything below into Claude Code, Codex, or another coding assistant that can run commands on your computer.

---

You are helping me clean up my own Android TV and install the Luma launcher on it. Work over ADB from this computer. Follow these rules for the whole session.

## Rules

- Use the Luma debloat kit for every change. Do not invent your own list of packages to remove.
- Only disable packages. Never uninstall anything, never factory reset, never flash, never change system partitions.
- Never touch a package marked `never` in the kit's lists, even if I ask. Tell me why instead.
- Show me the plan and wait for my "yes" before any step that changes the TV.
- Ask separately before the `aggressive` tier and before disabling the stock home screen. Explain what I would lose (for example voice search or Chromecast).
- If a command fails, stop and tell me what happened. Do not retry with stronger commands.
- Finish in one session and leave me with a way to undo everything.

## Steps

1. **Check the tools.** Confirm `adb` and `git` are installed. If `adb` is missing, tell me how to install Android platform-tools for my operating system and wait.

2. **Get the kit.** Clone `https://github.com/sharmaronit/LUMA` into a new folder, or update it if it is already there. Read `scripts/debloat/README.md` and the files in `scripts/debloat/lists/` before going further.

3. **Help me prepare the TV.** Ask me to:
   - open Settings > Device Preferences > About and press OK on "Build" seven times (Fire TV: Settings > My Fire TV > About),
   - switch on USB debugging or Network debugging in Developer options (Fire TV: ADB debugging),
   - tell you the TV's IP address from Settings > Network.

4. **Connect.** Run `adb connect <ip>:5555`. Ask me to tick "Always allow" and accept the prompt on the TV. Confirm with `adb devices` that the TV shows as `device`, not `unauthorized`.

5. **Dry run.** Run the kit with the dry-run flag (`debloat.ps1 -Ip <ip> -DryRun` on Windows, `./debloat.sh --ip <ip> --dry-run` elsewhere). Summarise for me, in plain language:
   - which TV it detected,
   - what the `safe` tier would switch off,
   - what the `aggressive` tier would add, and what each item is for.

6. **Clean.** After I agree, run the kit for real with the tiers I chose. Tell me where the backup file was saved.

7. **Install Luma.** Download the newest APK from `https://github.com/sharmaronit/LUMA/releases/latest`, install it with `adb install -r`, then run the kit with the set-launcher and compile options. If the TV refuses to change its Home app, explain the `disable-stock-launcher` option and ask before using it. On Fire TV, warn me that recent versions block other launchers and that this step may not work.

8. **Check.** Ask me to press Home on the remote and confirm that Luma opens, that Wi-Fi and the remote still work, and that my streaming apps still open. If anything is broken, restore from the backup straight away.

9. **Hand over.** Give me:
   - the list of what was switched off,
   - the exact restore command for my backup file,
   - a reminder to switch USB debugging off again in Developer options.
