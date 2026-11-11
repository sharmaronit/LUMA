import 'dart:typed_data';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:luma/database.dart';
import 'package:luma/providers/apps_service.dart';
import 'package:luma/models/category.dart';
import '../mocks.mocks.dart';

void main() {
  test(
    'category layout, favourite order and restore survive database reload',
    () async {
      SharedPreferences.setMockInitialValues({});
      final database = LumaDatabase.inMemory();
      final channel = MockLumaChannel();
      when(
        channel.getApplicationBanner(any),
      ).thenAnswer((_) async => Uint8List(0));
      when(
        channel.getApplicationIcon(any),
      ).thenAnswer((_) async => Uint8List(0));
      when(channel.getApplications()).thenAnswer(
        (_) async => [
          for (final id in ['a', 'b', 'c'])
            {
              'packageName': id,
              'name': id,
              'version': '1',
              'sideloaded': false,
              'appCategory': id == 'a' ? 0 : 1,
              'isGame': id == 'a',
            },
        ],
      );
      final service = AppsService(channel, database);
      for (var i = 0; i < 100 && !service.initialized; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(service.initialized, isTrue);
      expect(
        service.applications
            .firstWhere((app) => app.packageName == 'a')
            .appCategory,
        0,
      );
      expect(
        service.applications.firstWhere((app) => app.packageName == 'a').isGame,
        true,
      );
      final id = await service.addCategory(
        'Cinema',
        sort: CategorySort.alphabetical,
        type: CategoryType.row,
        columnsCount: 4,
        rowHeight: 140,
      );
      final saved = (await database.getCategories()).firstWhere(
        (c) => c.id == id,
      );
      expect(saved.columnsCount, 4);
      expect(saved.type, CategoryType.row);
      expect(saved.rowHeight, 140);
      expect(saved.sort, CategorySort.alphabetical);
      final favorites = await service.getOrCreateFavoritesCategory();
      final before = favorites.applications.map((a) => a.packageName).toList();
      await service.reorderApplication(favorites, 0, 1);
      final stored =
          (await database.getAppsCategories())
              .where((r) => r.categoryId == favorites.id)
              .toList()
            ..sort((a, b) => a.order.compareTo(b.order));
      expect(stored.first.appPackageName, before[1]);
      final a = service.applications.firstWhere(
        (app) => app.packageName == 'a',
      );
      await service.addToCategory(
        a,
        service.categories.firstWhere((c) => c.id == id),
      );
      await service.hideApplication(a);
      final backup = service.exportLayout();
      expect(
        (backup['categories'] as List).firstWhere(
          (c) => c['name'] == 'Cinema',
        )['apps'],
        contains('a'),
      );
      final namesBefore = (await database.getCategories())
          .map((c) => c.name)
          .toList();
      await expectLater(
        service.restoreLayout({
          'categories': [
            {'name': null},
          ],
          'hidden': [],
        }),
        throwsA(isA<TypeError>()),
      );
      expect(
        (await database.getCategories()).map((c) => c.name).toList(),
        namesBefore,
      );
      await service.restoreLayout({
        'categories': [
          {
            'name': 'Imported',
            'sort': 'manual',
            'type': 'grid',
            'columns': 3,
            'rowHeight': 110,
            'apps': ['missing', 'b', 'a'],
          },
        ],
        'hidden': ['b'],
      });
      expect(service.categories.single.name, 'Imported');
      expect(
        service.applications.firstWhere((a) => a.packageName == 'b').hidden,
        isTrue,
      );
      expect(
        ((await database.getAppsCategories())
              ..sort((a, b) => a.order.compareTo(b.order)))
            .map((r) => r.appPackageName)
            .toList(),
        ['b', 'a'],
      );
      await service.restoreLayout(backup);
      expect(
        service.applications.firstWhere((app) => app.packageName == 'a').isGame,
        true,
      );
      expect(service.categories.any((c) => c.name == 'Cinema'), isTrue);
      service.dispose();
      await database.close();
    },
  );
}
