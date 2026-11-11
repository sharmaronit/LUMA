# Rewrite plan: making Luma fully original

## Goal

Replace every part of Luma that came from earlier launchers (FLauncher, LTvLauncher, Arc Launcher) with newly written code. When none of their code is left, Luma can drop their notices, credit Ronit Sharma alone and choose any licence.

Until then the GPL applies: the copyright headers in the old files, the `LICENSE` and the `NOTICE` must stay.

## The one rule

New code is written from a description of what the feature must do, not by editing or translating the old file. A file that was reworded line by line is still a copy. For each part: write down the behaviour, write the tests, write a new implementation in a new file, switch the app over, then delete the old file.

## What is already original

- Everything in `lib/ronits/` (home screen, glass theme, quick settings, notifications, sleep timer, cleaner, wallpapers, first-run guide).
- `AdbClient.java`, `TvCleaner.java`, `TvControls.java`, `LumaNotificationListener.java`.
- `scripts/debloat/`, the README, `PROMPT.md` and the privacy text.

## What has to be replaced

About 50 files carry an upstream copyright header, and about 30 more were derived from upstream without one. In order of work:

| # | Part | Old files | Notes |
|---|---|---|---|
| 1 | Android bridge | `MainActivity.java`, the network, telephony and app-event handlers, `ClockScreensaverService.java` | Largest single piece (about 1,900 lines). Split into small classes per feature as it is rewritten. |
| 2 | Channel | `lib/luma_channel.dart` | Rewrite together with part 1; keep the method names so the rest of the app keeps working. |
| 3 | Data | `lib/database.dart`, `lib/models/`, `drift_schemas/` | New schema plus a one-time import of the user's existing favourites and settings. |
| 4 | Services | `lib/providers/` (apps, settings, wallpaper, network, watch next, brightness, updates) | One at a time; each already has tests that describe the behaviour. |
| 5 | App shell | `lib/main.dart`, `lib/luma.dart`, `lib/luma_app.dart`, `lib/actions.dart`, `lib/gradients.dart` | Small. |
| 6 | Old screens | `lib/widgets/` | Most are legacy panels the new settings page no longer opens. Delete the unused ones first; rewrite only what is still shown. |
| 7 | Translations and resources | `lib/l10n/`, Android `res/` | Rewrite the strings that are still used; drop the rest. |

## How to tell it is finished

- `git grep -l "Fesser\|Oscar Rojas\|LeanBitLab"` finds nothing outside `NOTICE`.
- No file in the repository existed in the first commit without having been rewritten under the rule above.
- All tests pass and the app has been checked on a TV.

Then, and only then: remove the upstream lines from `NOTICE` and from the in-app Licences & credits page, and choose the licence.

## A new repository

The finished rewrite should start a new repository with a clean history, because this repository's history contains the upstream code. The old repository stays available for as long as GPL builds made from it are distributed.
