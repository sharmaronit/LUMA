import '../ronits/launcher_backup.dart';
import '../ronits/clock_preferences.dart';
import '../ronits/solid_theme_scope.dart';
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

import 'package:luma/widgets/settings/back_button_actions.dart';
import 'package:flutter/material.dart';

import 'package:shared_preferences/shared_preferences.dart';

const _appHighlightAnimationEnabledKey = "app_highlight_animation_enabled";
const _appKeyClickEnabledKey = "app_key_click_enabled";
const _autoHideAppBar = "auto_hide_app_bar";
const _gradientUuidKey = "gradient_uuid";
const _backButtonAction = "back_button_action";
const _dateFormat = "date_format";
const _showCategoryTitles = "show_category_titles";
const _showAppNamesBelowIcons = "show_app_names_below_icons";
const _showDateInStatusBar = "show_date_in_status_bar";
const _showTimeInStatusBar = "show_time_in_status_bar";
const _timeFormat = "time_format";
const _wifiUsagePeriod = "wifi_usage_period";
const _showWifiWidgetInStatusBar = "show_wifi_widget_in_status_bar";
const String _showNetworkIndicatorInStatusBar =
    "show_network_indicator_in_status_bar";
const String _accentColor = "accent_color";
const String _screensaverClockStyle = "screensaver_clock_style";
const String _dockBackdropFilterDisabled = "dock_backdrop_filter_disabled";
const String _backgroundBlurDisabled = "background_blur_disabled";
const String _showWatchNextSection = "show_watch_next_section";
const String _dockDarkBackground = "dock_dark_background";
const String _dockShadowEnabled = "dock_shadow_enabled";
const String _showFocusBorders = "show_focus_borders";

// WiFi usage period options
const String WIFI_USAGE_DAILY = "daily";
const String WIFI_USAGE_WEEKLY = "weekly";
const String WIFI_USAGE_MONTHLY = "monthly";

// Accent color presets (hex values)
const String ACCENT_COLOR_PURPLE = "7C4DFF";
const String ACCENT_COLOR_TEAL = "00BFA5";
const String ACCENT_COLOR_BLUE = "2979FF";
const String ACCENT_COLOR_ORANGE = "FF6D00";
const String ACCENT_COLOR_PINK = "F50057";
const String ACCENT_COLOR_GREEN = "00C853";
const String ACCENT_COLOR_WHITE = "FFFFFF";
const String ACCENT_COLOR_YELLOW = "FFD600";
const String ACCENT_COLOR_RED = "D50000";
const String ACCENT_COLOR_CYAN = "00E5FF";
const String ACCENT_COLOR_INDIGO = "536DFE";
const String ACCENT_COLOR_LIME = "AEEA00";
const String ACCENT_COLOR_AMBER = "FFAB00";
const String ACCENT_COLOR_ROSE = "FF4081";
const String ACCENT_COLOR_ICE_BLUE = "80D8FF";

class SettingsService extends ChangeNotifier {
  static final defaultDateFormat = "EEEE d";
  static final defaultTimeFormat = "H:mm";
  final SharedPreferences _sharedPreferences;

  bool get appHighlightAnimationEnabled =>
      showFocusBorders &&
      (_sharedPreferences.getBool(_appHighlightAnimationEnabledKey) ?? false);

  bool get appKeyClickEnabled =>
      _sharedPreferences.getBool(_appKeyClickEnabledKey) ?? true;
  double get navigationSoundVolume =>
      (_sharedPreferences.getDouble('navigation_sound_volume') ?? .35).clamp(
        0,
        1,
      );
  Future<void> setNavigationSoundVolume(double value) async {
    if (!value.isFinite) return;
    await _sharedPreferences.setDouble(
      'navigation_sound_volume',
      value.clamp(0, 1),
    );
    notifyListeners();
  }

  bool get autoHideAppBarEnabled =>
      _sharedPreferences.getBool(_autoHideAppBar) ?? false;

  bool get showCategoryTitles =>
      _sharedPreferences.getBool(_showCategoryTitles) ?? false;

  bool get showAppNamesBelowIcons =>
      _sharedPreferences.getBool(_showAppNamesBelowIcons) ?? false;

  bool get showDateInStatusBar =>
      _sharedPreferences.getBool(_showDateInStatusBar) ?? false;

  bool get showTimeInStatusBar =>
      _sharedPreferences.getBool(_showTimeInStatusBar) ?? true;

  String? get gradientUuid => _sharedPreferences.getString(_gradientUuidKey);

  String get backButtonAction =>
      _sharedPreferences.getString(_backButtonAction) ??
      BACK_BUTTON_ACTION_NOTHING;

  String get dateFormat =>
      _sharedPreferences.getString(_dateFormat) ?? defaultDateFormat;

  String get clockStyle =>
      _sharedPreferences.getString('home_clock_style') == 'analog'
      ? 'analog'
      : 'digital';
  String get clockSize =>
      normaliseClockSize(_sharedPreferences.getString('home_clock_size'));
  Future<void> setClockStyle(String value) async {
    if (!['analog', 'digital'].contains(value)) return;
    await _sharedPreferences.setString('home_clock_style', value);
    notifyListeners();
  }

  Future<void> setClockSize(String value) async {
    if (!validClockSize(value)) return;
    await _sharedPreferences.setString('home_clock_size', value);
    notifyListeners();
  }

  String get timeFormat =>
      _sharedPreferences.getString(_timeFormat) ?? defaultTimeFormat;

  String get wifiUsagePeriod =>
      _sharedPreferences.getString(_wifiUsagePeriod) ?? WIFI_USAGE_DAILY;

  bool get showWifiWidgetInStatusBar =>
      _sharedPreferences.getBool(_showWifiWidgetInStatusBar) ?? false;

  bool get showNetworkIndicatorInStatusBar =>
      _sharedPreferences.getBool(_showNetworkIndicatorInStatusBar) ?? true;

  String get accentColorHex =>
      _sharedPreferences.getString(_accentColor) ?? ACCENT_COLOR_WHITE;

  String get screensaverClockStyle =>
      _sharedPreferences.getString(_screensaverClockStyle) ?? "minimal";

  bool get dockBackdropFilterDisabled =>
      _sharedPreferences.getBool(_dockBackdropFilterDisabled) ?? false;

  bool get backgroundBlurDisabled =>
      _sharedPreferences.getBool(_backgroundBlurDisabled) ?? false;

  bool get showWatchNextSection =>
      _sharedPreferences.getBool(_showWatchNextSection) ?? false;

  bool get dockDarkBackground =>
      _sharedPreferences.getBool(_dockDarkBackground) ?? false;

  bool get dockShadowEnabled =>
      _sharedPreferences.getBool(_dockShadowEnabled) ?? false;

  bool get showFocusBorders =>
      _sharedPreferences.getBool(_showFocusBorders) ?? true;

  String get launcherMaterial => 'minimal';
  Map<String, Object> exportBackupPreferences() =>
      LauncherBackup.preferencesFrom(_sharedPreferences);
  Future<void> restoreBackupPreferences(Map<String, Object> values) async {
    await LauncherBackup.applyPreferences(_sharedPreferences, values);
    notifyListeners();
  }

  Future<void> setClockFormat(String value) async {
    if (!['h:mm a', 'HH:mm'].contains(value)) return;
    await _sharedPreferences.setString(_timeFormat, value);
    notifyListeners();
  }

  String? get solidThemeColorHex =>
      _sharedPreferences.getString('solid_theme_color');

  /// Tells listeners the stored settings were replaced, as a profile switch
  /// does.
  void reload() => notifyListeners();

  /// Keeps the TV on while Luma's home screen is showing. Other apps keep
  /// the TV's own sleep setting, and Luma's sleep timer still turns it off.
  bool get keepScreenOn => _sharedPreferences.getBool('keep_screen_on') ?? true;
  Future<void> setKeepScreenOn(bool value) => set('keep_screen_on', value);

  /// The large clock behind the scenery on wallpapers that support it.
  bool get depthClock => _sharedPreferences.getBool('depth_clock') ?? true;
  Future<void> setDepthClock(bool value) => set('depth_clock', value);
  String? get selectedWallpaperAsset =>
      _sharedPreferences.getString('wallpaper_selected_asset');
  Future<void> setSelectedWallpaperAsset(String? asset) async {
    if (asset == null)
      await _sharedPreferences.remove('wallpaper_selected_asset');
    else
      await _sharedPreferences.setString('wallpaper_selected_asset', asset);
  }

  Future<void> setSolidThemeColor(String hex) async {
    if (!solidThemeColors.any((item) => item.hex == hex)) return;
    await _sharedPreferences.setString('solid_theme_color', hex);
    notifyListeners();
  }

  // ---------------------------------------------------------------- Lite mode
  // 'auto' turns Lite mode on for low-memory TVs; 'on' / 'off' override it.
  // Lite mode renders glass themes with the plain wallpaper and matte
  // controls, keeping the user's chosen theme for when it is switched off.
  //
  // Default is 'off': on a Mi Box 4 (2 GB, Mali-450) the plain wallpaper was
  // smoother than glass with one wallpaper (16 vs 32 dropped frames / 30 s)
  // but rougher with another (18-31 vs 2-8), so it is opt-in until Lite mode
  // has a recipe that measurably helps across wallpapers.
  static const liteModeValues = ['auto', 'on', 'off'];
  String get liteMode {
    final value = _sharedPreferences.getString('lite_mode');
    return liteModeValues.contains(value) ? value! : 'off';
  }

  /// Detected by [detectDeviceProfile]; cached so the first frame is right.
  bool get deviceLowEnd =>
      _sharedPreferences.getBool('device_low_end') ?? false;

  bool get liteModeActive => switch (liteMode) {
    'on' => true,
    'off' => false,
    _ => deviceLowEnd,
  };

  Future<void> setLiteMode(String value) async {
    if (!liteModeValues.contains(value)) return;
    await _sharedPreferences.setString('lite_mode', value);
    notifyListeners();
  }

  /// Low end = Android's low-RAM flag, or 2.5 GB of RAM or less (typical
  /// 1-2 GB sticks and boxes).
  static bool isLowEndProfile(Map<String, dynamic> profile) {
    if (profile['isLowRamDevice'] == true) return true;
    final total = (profile['totalMemBytes'] as num?)?.toDouble();
    return total != null && total > 0 && total <= 2.5 * 1024 * 1024 * 1024;
  }

  Future<void> detectDeviceProfile(
    Future<Map<String, dynamic>> Function() load,
  ) async {
    try {
      final lowEnd = isLowEndProfile(await load());
      if (lowEnd == deviceLowEnd &&
          _sharedPreferences.containsKey('device_low_end'))
        return;
      await _sharedPreferences.setBool('device_low_end', lowEnd);
      notifyListeners();
    } catch (error) {
      debugPrint('Device profile unavailable: $error');
    }
  }

  /// The theme the user picked. Use this when reading or saving the choice.
  /// There is one Liquid Glass theme now; the heavier live-blur variant
  /// ('glass-real') is read as it.
  String get selectedMinimalBackground {
    final stored = _sharedPreferences.getString('minimal_background');
    if (stored == 'glass-real') return 'glass';
    return ['wallpaper', 'glass'].contains(stored) ? stored! : 'charcoal';
  }

  /// The theme actually rendered: glass themes fall back to the plain
  /// wallpaper while Lite mode is active.
  String get minimalBackground {
    final selected = selectedMinimalBackground;
    if (liteModeActive && (selected == 'glass' || selected == 'glass-real'))
      return 'wallpaper';
    return selected;
  }

  Future<void> setMinimalBackground(String value) async {
    if (value == 'glass-real') value = 'glass';
    if (!['charcoal', 'wallpaper', 'glass'].contains(value)) return;
    await _sharedPreferences.setString('minimal_background', value);
    if (value == 'wallpaper' || value == 'charcoal')
      await _sharedPreferences.setString('minimal_last_background', value);
    notifyListeners();
  }

  bool get reduceMotion => _sharedPreferences.getBool('reduce_motion') ?? false;
  bool get performanceMode =>
      _sharedPreferences.getBool('performance_mode') ?? true;
  bool get useRonitsHome =>
      _sharedPreferences.getBool('use_ronits_home') ?? true;
  bool get launcherSetupSeen =>
      (_sharedPreferences.getInt('launcher_setup_version') ?? 0) >= 2;
  Future<void> setLauncherMaterial(String value) async {
    if (!['minimal', 'lite', 'frosted', 'ronits', 'solid'].contains(value))
      return;
    await _sharedPreferences.setString('launcher_material', 'minimal');
    notifyListeners();
  }

  Future<void> setReduceMotion(bool value) => set('reduce_motion', value);
  Future<void> setPerformanceMode(bool value) => set('performance_mode', value);
  Future<void> setUseRonitsHome(bool value) => set('use_ronits_home', value);
  Future<void> setLauncherSetupSeen(bool value) async {
    await _sharedPreferences.setBool('launcher_setup_seen', value);
    await _sharedPreferences.setInt('launcher_setup_version', value ? 2 : 0);
    notifyListeners();
  }

  Color get accentColor {
    final hex = accentColorHex;
    return RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(hex)
        ? Color(0xFF000000 | int.parse(hex, radix: 16))
        : Colors.white;
  }

  SettingsService(this._sharedPreferences) {
    final stored = _sharedPreferences.getString('launcher_material');
    if (stored != null && stored != 'minimal')
      unawaited(_sharedPreferences.setString('launcher_material', 'minimal'));
  }

  Future<void> set(String key, bool value) async {
    await _sharedPreferences.setBool(key, value);
    notifyListeners();
  }

  Future<void> setAppHighlightAnimationEnabled(bool value) async {
    if (value && !showFocusBorders) {
      return;
    }
    return set(_appHighlightAnimationEnabledKey, value);
  }

  Future<void> setAppKeyClickEnabled(bool value) async {
    return set(_appKeyClickEnabledKey, value);
  }

  Future<void> setAutoHideAppBarEnabled(bool value) async {
    return set(_autoHideAppBar, value);
  }

  Future<void> setGradientUuid(String value) async {
    await _sharedPreferences.setString(_gradientUuidKey, value);
    notifyListeners();
  }

  Future<void> setBackButtonAction(String value) async {
    await _sharedPreferences.setString(_backButtonAction, value);
    notifyListeners();
  }

  Future<void> setDateTimeFormat(
    String dateFormatString,
    String timeFormatString,
  ) async {
    await Future.wait([
      _sharedPreferences.setString(_dateFormat, dateFormatString),
      _sharedPreferences.setString(_timeFormat, timeFormatString),
    ]);
    notifyListeners();
  }

  Future<void> setShowCategoryTitles(bool show) async {
    return set(_showCategoryTitles, show);
  }

  Future<void> setShowAppNamesBelowIcons(bool show) async {
    return set(_showAppNamesBelowIcons, show);
  }

  Future<void> setShowDateInStatusBar(bool show) async {
    return set(_showDateInStatusBar, show);
  }

  Future<void> setShowTimeInStatusBar(bool show) async {
    return set(_showTimeInStatusBar, show);
  }

  Future<void> setWifiUsagePeriod(String period) async {
    await _sharedPreferences.setString(_wifiUsagePeriod, period);
    notifyListeners();
  }

  Future<void> setShowWifiWidgetInStatusBar(bool show) async {
    return set(_showWifiWidgetInStatusBar, show);
  }

  Future<void> setShowNetworkIndicatorInStatusBar(bool show) async {
    return set(_showNetworkIndicatorInStatusBar, show);
  }

  Future<void> setAccentColor(String colorHex) async {
    await _sharedPreferences.setString(_accentColor, colorHex);
    notifyListeners();
  }

  Future<void> setScreensaverClockStyle(String style) async {
    await _sharedPreferences.setString(_screensaverClockStyle, style);
    notifyListeners();
  }

  Future<void> setDockBackdropFilterDisabled(bool value) async {
    return set(_dockBackdropFilterDisabled, value);
  }

  Future<void> setBackgroundBlurDisabled(bool value) async {
    return set(_backgroundBlurDisabled, value);
  }

  Future<void> setShowWatchNextSection(bool value) async {
    return set(_showWatchNextSection, value);
  }

  Future<void> setDockDarkBackground(bool value) async {
    return set(_dockDarkBackground, value);
  }

  Future<void> setDockShadowEnabled(bool value) async {
    return set(_dockShadowEnabled, value);
  }

  Future<void> setShowFocusBorders(bool value) async {
    await set(_showFocusBorders, value);
    if (!value) {
      await setAppHighlightAnimationEnabled(false);
    }
  }

  bool get timeBasedWallpaperEnabled =>
      _sharedPreferences.getBool("time_based_wallpaper_enabled") ?? false;

  Future<void> setTimeBasedWallpaperEnabled(bool enabled) async {
    await _sharedPreferences.setBool("time_based_wallpaper_enabled", enabled);
    notifyListeners();
  }
}
