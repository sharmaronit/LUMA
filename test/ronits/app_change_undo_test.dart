import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mockito/mockito.dart';
import 'package:luma/database.dart';
import 'package:luma/providers/apps_service.dart';
import 'package:luma/widgets/settings/app_change_undo.dart';
import '../mocks.mocks.dart';

void main() {
  test('native Undo restores dock order and hidden state in SQLite', () async {
    SharedPreferences.setMockInitialValues({});
    final database = LumaDatabase.inMemory();
    final channel = MockLumaChannel();
    when(
      channel.getApplicationBanner(any),
    ).thenAnswer((_) async => Uint8List(0));
    when(channel.getApplicationIcon(any)).thenAnswer((_) async => Uint8List(0));
    when(channel.getApplications()).thenAnswer(
      (_) async => [
        for (final id in ['a', 'b', 'c'])
          {'packageName': id, 'name': id, 'version': '1', 'sideloaded': false},
      ],
    );
    final service = AppsService(channel, database);
    for (var i = 0; i < 100 && !service.initialized; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(service.initialized, isTrue);
    final favorites = await service.getOrCreateFavoritesCategory();
    final before = favorites.applications
        .map((app) => app.packageName)
        .toList();
    final app = favorites.applications[1];
    final removal = await toggleFavoriteWithUndo(service, app);
    expect(service.isAppInFavorites(app), isFalse);
    await removal!.restore();
    expect(favorites.applications.map((app) => app.packageName), before);
    final stored =
        (await database.getAppsCategories())
            .where((row) => row.categoryId == favorites.id)
            .toList()
          ..sort((a, b) => a.order.compareTo(b.order));
    expect(stored.map((row) => row.appPackageName), before);
    final hidden = await toggleHiddenWithUndo(service, app);
    expect(app.hidden, isTrue);
    await hidden!.restore();
    expect(app.hidden, isFalse);
    expect(
      (await database.getApplications())
          .firstWhere((row) => row.packageName == app.packageName)
          .hidden,
      isFalse,
    );
    expect(favorites.applications.map((app) => app.packageName), before);
    service.dispose();
    await database.close();
  });
}
