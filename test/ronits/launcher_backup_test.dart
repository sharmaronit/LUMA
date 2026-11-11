import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:luma/ronits/launcher_backup.dart';

Map<String, dynamic> category({List<String> apps = const ['a', 'b']}) => {
  'name': 'Favorites',
  'sort': 'manual',
  'type': 'row',
  'columns': 6,
  'rowHeight': 110,
  'apps': apps,
};
void main() {
  test('backup round trip preserves settings and app order', () async {
    SharedPreferences.setMockInitialValues({
      'launcher_material': 'solid',
      'solid_theme_color': '183C32',
      'time_format': 'HH:mm',
      'performance_mode': true,
      'unrelated_secret': 'never exported',
    });
    final prefs = await SharedPreferences.getInstance();
    final source = LauncherBackup(LauncherBackup.preferencesFrom(prefs), {
      'categories': [
        category(apps: ['b', 'a']),
      ],
      'hidden': ['c'],
    }).encode();
    expect(source, isNot(contains('unrelated_secret')));
    final parsed = LauncherBackup.parse(source);
    await prefs.setString('launcher_material', 'lite');
    await LauncherBackup.applyPreferences(prefs, parsed.preferences);
    expect(prefs.getString('launcher_material'), 'minimal');
    expect(prefs.getString('solid_theme_color'), '183C32');
    expect((parsed.layout['categories'] as List).single['apps'], ['b', 'a']);
    expect(prefs.getString('unrelated_secret'), 'never exported');
  });
  test('invalid backups are rejected before restoration', () {
    final base = {
      'format': 'luma-backup',
      'version': 1,
      'preferences': {'launcher_material': 'solid'},
      'layout': {
        'categories': [category()],
        'hidden': [],
      },
    };
    expect(() => LauncherBackup.parse('{bad json'), throwsFormatException);
    expect(
      () => LauncherBackup.parse(jsonEncode({...base, 'version': 99})),
      throwsFormatException,
    );
    expect(
      () => LauncherBackup.parse(
        jsonEncode({
          ...base,
          'preferences': {'custom_banner_com.app': '/private/file'},
        }),
      ),
      throwsFormatException,
    );
    expect(
      () => LauncherBackup.parse(
        jsonEncode({
          ...base,
          'layout': {
            'categories': [
              category(apps: ['a', 'a']),
            ],
            'hidden': [],
          },
        }),
      ),
      throwsFormatException,
    );
    expect(
      () => LauncherBackup.parse(
        jsonEncode({
          ...base,
          'layout': {
            'categories': [
              {...category(), 'columns': 9000},
            ],
            'hidden': [],
          },
        }),
      ),
      throwsFormatException,
    );
    expect(
      () => LauncherBackup.parse('x' * (1024 * 1024 + 1)),
      throwsFormatException,
    );
  });
}
