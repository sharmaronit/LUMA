import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'solid_theme_scope.dart';
import 'clock_preferences.dart';
import 'scenery_wallpapers.dart';

/// Portable settings only. Never imports permissions, paths, updater ownership or app APKs.
const backupPreferenceKeys = {
  'launcher_font_style',
  'home_card_size',
  'home_wallpaper_accent',
  'home_remember_selection',
  'home_row_order',
  'home_show_watch',
  'home_show_recent',
  'launcher_material',
  'minimal_background',
  'solid_theme_color',
  'reduce_motion',
  'performance_mode',
  'time_format',
  'home_clock_style',
  'home_clock_size',
  'show_watch_next_section',
  'preview_wallpaper',
  'preview_favorites',
  'preview_hidden',
  'preview_grid_columns',
  'app_key_click_enabled',
  'navigation_sound_volume',
  'show_focus_borders',
  'show_app_names_below_icons',
};

class LauncherBackup {
  LauncherBackup(this.preferences, this.layout);
  final Map<String, Object> preferences;
  final Map<String, dynamic> layout;
  String encode() => const JsonEncoder.withIndent('  ').convert({
    'format': 'luma-backup',
    'version': 1,
    'preferences': preferences,
    'layout': layout,
  });
  static Map<String, Object> preferencesFrom(SharedPreferences prefs) => {
    for (final key in backupPreferenceKeys)
      if (prefs.get(key) != null)
        key: key == 'launcher_material' ? 'minimal' : prefs.get(key)!,
  };
  static LauncherBackup parse(String source) {
    if (utf8.encode(source).length > 1024 * 1024)
      throw const FormatException('Backup exceeds 1 MB.');
    final data = jsonDecode(source);
    if (data is! Map || data['format'] != 'luma-backup' || data['version'] != 1)
      throw const FormatException('Unsupported Luma backup.');
    final rawPrefs = data['preferences'];
    final rawLayout = data['layout'];
    if (rawPrefs is! Map || rawLayout is! Map)
      throw const FormatException('Missing preferences or layout.');
    final prefs = <String, Object>{};
    for (final entry in rawPrefs.entries) {
      final key = entry.key;
      final value = entry.value;
      if (!backupPreferenceKeys.contains(key))
        throw const FormatException('Unknown preference.');
      bool valid;
      switch (key) {
        case 'launcher_font_style':
          valid = [
            'current',
            'rounded',
            'geometric',
            'classic',
          ].contains(value);
        case 'home_card_size':
          valid = value is String && validClockSize(value);
        case 'home_row_order':
          valid =
              value is List &&
              value.length == 2 &&
              value.toSet().length == 2 &&
              value.every((v) => ['watch', 'recent'].contains(v));
        case 'launcher_material':
          valid = [
            'minimal',
            'ronits',
            'solid',
            'lite',
            'frosted',
          ].contains(value);
        case 'minimal_background':
          valid = [
            'oxygen-white',
            'oxygen-black',
            'charcoal',
            'black',
            'chocolate',
            'wallpaper',
            'glass',
            'glass-real',
          ].contains(value);
        case 'solid_theme_color':
          valid = solidThemeColors.any((color) => color.hex == value);
        case 'home_clock_style':
          valid = ['analog', 'digital'].contains(value);
        case 'home_clock_size':
          valid = value is String && validClockSize(value);
        case 'time_format':
          valid = value is String && value.isNotEmpty && value.length <= 80;
        case 'preview_wallpaper':
          valid =
              value is String &&
              sceneryWallpapers.any((photo) => photo.asset == value);
        case 'navigation_sound_volume':
          valid = value is num && value.isFinite && value >= 0 && value <= 1;
        case 'preview_favorites':
        case 'preview_hidden':
          valid = _ids(value);
        case 'preview_grid_columns':
          valid = value is int && value >= 3 && value <= 8;
        default:
          valid = value is bool;
      }
      if (!valid) throw FormatException('Invalid $key.');
      prefs[key as String] = key == 'launcher_material'
          ? 'minimal'
          : value is List
          ? value.cast<String>()
          : value as Object;
    }
    final categories = rawLayout['categories'];
    final hidden = rawLayout['hidden'];
    if (categories is! List || categories.length > 100 || !_ids(hidden))
      throw const FormatException('Invalid app layout.');
    final names = <String>{};
    for (final category in categories) {
      if (category is! Map ||
          category['name'] is! String ||
          (category['name'] as String).trim().isEmpty ||
          (category['name'] as String).length > 100 ||
          !names.add(category['name']) ||
          !['manual', 'alphabetical', 'lastUsed'].contains(category['sort']) ||
          !['row', 'grid'].contains(category['type']) ||
          category['columns'] is! int ||
          category['columns'] < 3 ||
          category['columns'] > 8 ||
          category['rowHeight'] is! int ||
          category['rowHeight'] < 40 ||
          category['rowHeight'] > 400 ||
          !_ids(category['apps']))
        throw const FormatException('Invalid category.');
    }
    final spacers = rawLayout['spacers'] ?? [];
    if (spacers is! List ||
        spacers.length > 100 ||
        spacers.any(
          (s) =>
              s is! Map ||
              s['height'] is! int ||
              s['height'] < 0 ||
              s['height'] > 1000 ||
              s['order'] is! int ||
              s['order'] < 0 ||
              s['order'] > 200,
        ))
      throw const FormatException('Invalid spacing.');
    for (final category in categories) {
      final order = category['order'];
      if (order != null && (order is! int || order < 0 || order > 200))
        throw const FormatException('Invalid category order.');
    }
    return LauncherBackup(prefs, {
      'categories': [for (final c in categories) Map<String, dynamic>.from(c)],
      'spacers': [
        for (final spacer in spacers) Map<String, dynamic>.from(spacer),
      ],
      'hidden': (hidden as List).cast<String>(),
    });
  }

  static bool _ids(Object? value) =>
      value is List &&
      value.length <= 1000 &&
      value.every((id) => id is String && id.isNotEmpty && id.length <= 256) &&
      value.toSet().length == value.length;
  static Future<void> applyPreferences(
    SharedPreferences prefs,
    Map<String, Object> values,
  ) async {
    for (final key in backupPreferenceKeys) {
      final value = values[key];
      final bool saved;
      if (value == null) {
        saved = await prefs.remove(key);
      } else if (value is bool) {
        saved = await prefs.setBool(key, value);
      } else if (value is int) {
        saved = key == 'navigation_sound_volume'
            ? await prefs.setDouble(key, value.toDouble())
            : await prefs.setInt(key, value);
      } else if (value is double) {
        saved = await prefs.setDouble(key, value);
      } else if (value is String) {
        saved = await prefs.setString(key, value);
      } else {
        saved = await prefs.setStringList(key, (value as List).cast<String>());
      }
      if (!saved) throw StateError('Unable to save $key');
    }
  }

  String get summary =>
      '${(layout['categories'] as List).length} app collections · ${(layout['hidden'] as List).length} hidden apps · ${preferences.length} preferences';
}
