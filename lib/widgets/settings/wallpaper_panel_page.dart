/*
 * FLauncher
 * Copyright (C) 2021  Étienne Fesser
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

import 'package:luma/providers/settings_service.dart';
import 'package:luma/providers/wallpaper_service.dart';
import 'package:luma/widgets/settings/focusable_settings_tile.dart';
import 'package:luma/widgets/settings/gradient_panel_page.dart';
import 'package:luma/widgets/tv_media_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:luma/l10n/app_localizations.dart';

import 'package:luma/widgets/rounded_switch_list_tile.dart';

class WallpaperPanelPage extends StatelessWidget {
  static const String routeName = "wallpaper_panel";

  @override
  Widget build(BuildContext context) {
    AppLocalizations localizations = AppLocalizations.of(context)!;
    final clean = context.select<SettingsService, bool>(
      (s) => s.useRonitsHome && s.launcherMaterial == 'minimal',
    );

    return Column(
      children: [
        Text(
          localizations.wallpaper,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        Divider(),
        Consumer<SettingsService>(
          builder: (_, settings, __) {
            return RoundedSwitchListTile(
              title: Text(localizations.timeBasedWallpaper),
              secondary: Icon(Icons.access_time),
              value: settings.timeBasedWallpaperEnabled,
              onChanged: (value) =>
                  settings.setTimeBasedWallpaperEnabled(value),
            );
          },
        ),
        Consumer<SettingsService>(
          builder: (_, settings, __) {
            if (settings.timeBasedWallpaperEnabled) {
              return Column(
                children: [
                  FocusableSettingsTile(
                    leading: Icon(Icons.wb_sunny),
                    title: Text(localizations.pickDayWallpaper),
                    onPressed: () => _pickWallpaper(
                      context,
                      (s, media) => s.pickWallpaperDayFromUri(media.uri),
                      false,
                    ),
                  ),
                  if (!clean)
                    FocusableSettingsTile(
                      leading: Icon(Icons.videocam_outlined),
                      title: Text(localizations.pickDayVideoWallpaper),
                      onPressed: () => _pickWallpaper(
                        context,
                        (s, media) => s.pickVideoWallpaperFromUri(
                          media.uri,
                          period: 'day',
                        ),
                        true,
                      ),
                    ),
                  FocusableSettingsTile(
                    leading: Icon(Icons.nights_stay),
                    title: Text(localizations.pickNightWallpaper),
                    onPressed: () => _pickWallpaper(
                      context,
                      (s, media) => s.pickWallpaperNightFromUri(media.uri),
                      false,
                    ),
                  ),
                  if (!clean)
                    FocusableSettingsTile(
                      leading: Icon(Icons.videocam_outlined),
                      title: Text(localizations.pickNightVideoWallpaper),
                      onPressed: () => _pickWallpaper(
                        context,
                        (s, media) => s.pickVideoWallpaperFromUri(
                          media.uri,
                          period: 'night',
                        ),
                        true,
                      ),
                    ),
                ],
              );
            } else {
              return Column(
                children: [
                  if (!clean)
                    FocusableSettingsTile(
                      autofocus: true,
                      leading: Icon(Icons.gradient),
                      title: Text(
                        localizations.gradient,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      onPressed: () => Navigator.of(
                        context,
                      ).pushNamed(GradientPanelPage.routeName),
                    ),
                  FocusableSettingsTile(
                    autofocus: clean,
                    leading: Icon(Icons.insert_drive_file_outlined),
                    title: Text(
                      localizations.picture,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    onPressed: () => _pickWallpaper(
                      context,
                      (s, media) => s.pickWallpaperFromUri(media.uri),
                      false,
                    ),
                  ),
                  if (!clean)
                    FocusableSettingsTile(
                      leading: Icon(Icons.videocam_outlined),
                      title: Text(
                        localizations.video,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      onPressed: () => _pickWallpaper(
                        context,
                        (s, media) => s.pickVideoWallpaperFromUri(media.uri),
                        true,
                      ),
                    ),
                ],
              );
            }
          },
        ),
      ],
    );
  }

  Future<void> _pickWallpaper(
    BuildContext context,
    Future<void> Function(WallpaperService, TvMediaSelection) action,
    bool isVideo,
  ) async {
    final media = await TvMediaPicker.show(
      context,
      mode: isVideo ? TvMediaPickerMode.video : TvMediaPickerMode.image,
    );
    if (media != null && context.mounted) {
      await action(context.read<WallpaperService>(), media);
      if (context.mounted) {
        final settings = context.read<SettingsService>();
        if (settings.useRonitsHome &&
            settings.launcherMaterial == 'minimal' &&
            !['glass', 'glass-real'].contains(settings.selectedMinimalBackground))
          await settings.setMinimalBackground('wallpaper');
      }
    }
  }
}
