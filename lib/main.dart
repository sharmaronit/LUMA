import 'ronits/typography.dart';
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

import 'dart:async';

import 'package:luma/database.dart';
import 'package:luma/luma_channel.dart';
import 'package:luma/providers/apps_service.dart';
import 'package:luma/providers/launcher_state.dart';
import 'package:luma/providers/network_service.dart';
import 'package:luma/providers/settings_service.dart';
import 'package:luma/providers/brightness_service.dart';
import 'package:luma/providers/wallpaper_service.dart';
import 'package:luma/providers/watch_next_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'luma_app.dart';
import 'ronits/profiles.dart';
import 'ronits/frame_probe.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  startFrameProbe();
  registerLumaFontLicense();
  initializeDateFormatting();

  final sharedPreferences = await SharedPreferences.getInstance();
  final lumaChannel = LumaChannel();
  final lumaDatabase = LumaDatabase(connect());

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) =>
              SettingsService(sharedPreferences)
                ..detectDeviceProfile(LumaChannel().getDeviceProfile),
          lazy: false,
        ),
        ChangeNotifierProvider(
          create: (_) => AppsService(lumaChannel, lumaDatabase),
        ),
        ChangeNotifierProvider(create: (_) => LauncherState()),
        ChangeNotifierProvider(create: (_) => NetworkService(lumaChannel)),
        ChangeNotifierProvider(
          create: (context) {
            SettingsService settingsService = Provider.of(
              context,
              listen: false,
            );
            return WallpaperService(settingsService);
          },
        ),
        ChangeNotifierProvider(
          create: (context) => ProfileService(
            sharedPreferences,
            host: _AppProfileHost(
              context.read<AppsService>(),
              context.read<WallpaperService>(),
              context.read<SettingsService>(),
            ),
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => BrightnessService(sharedPreferences),
          lazy: false,
        ),
        ChangeNotifierProvider(
          create: (_) => WatchNextService(lumaChannel),
          lazy: false,
        ),
      ],
      child: LumaApp(),
    ),
  );
}

class _AppProfileHost implements ProfileHost {
  _AppProfileHost(this.apps, this.wallpaper, this.settings);
  final AppsService apps;
  final WallpaperService wallpaper;
  final SettingsService settings;
  @override
  Future<List<String>> favourites() async => apps.favoritePackages;
  @override
  Future<void> setFavourites(List<String> packages) =>
      apps.setFavoritePackages(packages);
  @override
  Future<void> saveWallpaper(String profileId) =>
      wallpaper.saveProfileWallpaper(profileId);
  @override
  Future<void> restoreWallpaper(String profileId) =>
      wallpaper.restoreProfileWallpaper(profileId);
  @override
  Future<void> deleteWallpaper(String profileId) =>
      wallpaper.deleteProfileWallpaper(profileId);
  @override
  void settingsChanged() => settings.reload();
}
