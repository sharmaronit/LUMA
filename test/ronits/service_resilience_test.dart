import 'dart:async';
import 'dart:io';

import 'package:luma/luma_channel.dart';
import 'package:luma/providers/network_service.dart';
import 'package:luma/providers/apps_service.dart';
import 'package:luma/providers/settings_service.dart';
import 'package:luma/providers/wallpaper_service.dart';
import 'package:luma/providers/watch_next_service.dart';
import 'package:luma/ronits/launcher_backup.dart';
import 'package:luma/ronits/programme_library.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:mockito/mockito.dart';
import '../mocks.mocks.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

class _AppsChannel extends LumaChannel {
  bool unavailable = true;
  int bannerLoads = 0;
  var banner = Completer<Uint8List>();
  @override
  Future<List<Map<dynamic, dynamic>>> getApplications() async {
    if (unavailable) throw PlatformException(code: 'unavailable');
    return [];
  }

  @override
  void addAppsChangedListener(void Function(Map<String, dynamic>) listener) {}
  @override
  void removeAppsChangedListener(
    void Function(Map<String, dynamic>) listener,
  ) {}
  @override
  Future<Uint8List> getApplicationBanner(String packageName) {
    bannerLoads++;
    return banner.future;
  }
}

class _FailingPreferences extends InMemorySharedPreferencesStore {
  _FailingPreferences() : super.empty();
  @override
  Future<bool> setValue(String valueType, String key, Object value) async =>
      false;
}

class _Network extends LumaChannel {
  final permission = Completer<bool>();
  void Function(Map<String, dynamic>)? listener;
  bool removed = false;
  @override
  void addNetworkChangedListener(void Function(Map<String, dynamic>) value) =>
      listener = value;
  @override
  void removeNetworkChangedListener(
    void Function(Map<String, dynamic>) value,
  ) => removed = value == listener;
  @override
  Future<Map<String, dynamic>> getActiveNetworkInformation() async => {
    'networkType': 999,
    'internetAccess': true,
  };
  @override
  Future<bool> checkUsageStatsPermission() => permission.future;
  @override
  Future<int> getDailyWifiUsage() async => 123;
}

class _Programmes extends LumaChannel {
  Future<bool> Function() permission = () async => true;
  Future<List<Map<dynamic, dynamic>>> Function() query = () async => [
    {
      'id': 1,
      'title': 'A show',
      'packageName': 'tv.app',
      'posterUri': 'content://poster/1',
    },
  ];
  final images = <String, Completer<Uint8List>>{};
  int active = 0, maximum = 0;
  @override
  Future<bool> checkWatchNextPermission() => permission();
  @override
  Future<List<Map<dynamic, dynamic>>> getWatchNextItems() => query();
  @override
  Future<Uint8List> loadContentUriImage(String uri) async {
    active++;
    if (active > maximum) maximum = active;
    try {
      return await images.putIfAbsent(uri, Completer<Uint8List>.new).future;
    } finally {
      active--;
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'app discovery failure is recoverable and empty artwork is cached',
    () async {
      final channel = _AppsChannel();
      final database = MockLumaDatabase();
      when(database.getApplications()).thenAnswer((_) async => []);
      when(database.getAppsCategories()).thenAnswer((_) async => []);
      when(database.getCategories()).thenAnswer((_) async => []);
      when(database.getLauncherSpacers()).thenAnswer((_) async => []);
      when(database.persistApps(any)).thenAnswer((_) async {});
      when(database.deleteApps(any)).thenAnswer((_) async {});
      when(
        database.transaction(any),
      ).thenAnswer((call) => (call.positionalArguments.first as Function)());
      when(database.wasCreated).thenReturn(false);
      final service = AppsService(channel, database);
      addTearDown(service.dispose);
      await Future<void>.delayed(Duration.zero);
      expect(service.initialized, false);
      expect(service.initializationError, isA<PlatformException>());
      channel.unavailable = false;
      await service.initialize();
      expect(service.initialized, true);
      expect(service.initializationError, isNull);
      final first = service.getAppBanner('app');
      final second = service.getAppBanner('app');
      channel.banner.complete(Uint8List(0));
      await Future.wait([first, second]);
      await service.getAppBanner('app');
      expect(channel.bannerLoads, 1);
      channel.banner = Completer<Uint8List>();
      final stale = service.getAppBanner('changing-app');
      while (channel.bannerLoads < 2) {
        await Future<void>.delayed(Duration.zero);
      }
      final folder = await Directory.systemTemp.createTemp('luma-artwork-');
      try {
        final custom = File('${folder.path}/banner');
        await custom.writeAsBytes([7, 8, 9]);
        await service.setCustomAppBanner('changing-app', custom.path);
        expect(await service.getAppBanner('changing-app'), [7, 8, 9]);
        channel.banner.complete(Uint8List.fromList([1, 2, 3]));
        await stale;
        expect(await service.getAppBanner('changing-app'), [7, 8, 9]);
      } finally {
        await folder.delete(recursive: true);
      }
    },
  );

  test(
    'failed image and video imports preserve existing wallpaper files',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'luma-wallpaper-',
      );
      final previousPaths = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _Paths(directory.path);
      final settings = SettingsService(await SharedPreferences.getInstance());
      final service = WallpaperService(settings);
      addTearDown(() async {
        service.dispose();
        settings.dispose();
        PathProviderPlatform.instance = previousPaths;
        await directory.delete(recursive: true);
      });
      while (!service.isInitialized) {
        await Future<void>.delayed(Duration.zero);
      }
      final image = File('${directory.path}/wallpaper');
      final video = File('${directory.path}/wallpaper_video');
      await image.writeAsBytes([1, 2, 3]);
      await video.writeAsBytes([4, 5, 6]);
      final missing = File('${directory.path}/missing');
      await expectLater(
        service.pickWallpaper(missing),
        throwsA(isA<FileSystemException>()),
      );
      expect(await image.readAsBytes(), [1, 2, 3]);
      expect(await video.readAsBytes(), [4, 5, 6]);
      await expectLater(
        service.pickVideoWallpaper(missing),
        throwsA(isA<FileSystemException>()),
      );
      expect(await image.readAsBytes(), [1, 2, 3]);
      expect(await video.readAsBytes(), [4, 5, 6]);
      expect(
        directory.listSync().where((file) => file.path.endsWith('.tmp')),
        isEmpty,
      );
    },
  );

  testWidgets(
    'network initialization updates listeners and disposal cancels pending polling',
    (tester) async {
      final channel = _Network();
      final service = NetworkService(channel);
      var changes = 0;
      service.addListener(() => changes++);
      await tester.pump();
      expect(changes, greaterThan(0));
      expect(service.networkType, NetworkType.Unknown);
      channel.listener!({'name': 'CELLULAR_STATE_CHANGED', 'arguments': -100});
      expect(service.cellularNetworkType, CellularNetworkType.Unknown);
      service.dispose();
      channel.permission.complete(true);
      await tester.pump();
      expect(channel.removed, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'disposing during programme permission check leaves no polling timer',
    (tester) async {
      final pending = Completer<bool>();
      final channel = _Programmes()..permission = () => pending.future;
      final service = WatchNextService(channel);
      service.dispose();
      pending.complete(true);
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('poster work is bounded and completes safely after disposal', (
    tester,
  ) async {
    final channel = _Programmes()..query = () async => [];
    final service = WatchNextService(channel);
    await tester.pump();
    for (var i = 0; i < 5; i++) {
      service.ensurePosterLoaded('content://poster/$i');
    }
    await tester.pump();
    expect(channel.maximum, 2);
    service.dispose();
    for (final image in channel.images.values) {
      image.complete(Uint8List.fromList([1, 2, 3]));
    }
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'failed programme refresh retains titles and reports the provider error',
    (tester) async {
      final channel = _Programmes();
      final service = WatchNextService(channel);
      await tester.pump();
      expect(service.items.single.title, 'A show');
      channel.query = () async => throw PlatformException(code: 'offline');
      await expectLater(
        service.refreshPermissionAndItems(),
        throwsA(isA<PlatformException>()),
      );
      expect(service.items.single.title, 'A show');
      expect(ProgrammeLibrary.shared.source.single.item.title, 'A show');
      expect(service.isLoading, isFalse);
      expect(
        ProgrammeLibrary.shared.sourceError,
        contains('Could not refresh'),
      );
      service.dispose();
      for (final image in channel.images.values) {
        image.complete(Uint8List(0));
      }
      await tester.pump();
    },
  );

  test(
    'invalid stored accent colours fall back without crashing startup',
    () async {
      SharedPreferences.setMockInitialValues({
        'accent_color': 'not a colour',
      });
      final settings = SettingsService(
        await SharedPreferences.getInstance(),
      );
      expect(settings.accentColor.toARGB32(), 0xffffffff);
      settings.dispose();
    },
  );

  test(
    'programme hide and Undo roll back when preference writes fail',
    () async {
      final library = ProgrammeLibrary();
      await library.ready();
      final entry = ProgrammeEntry.fromMap({
        'item': {'id': 9, 'title': 'A show'},
        'provider': 'TV app',
      });
      final previousStore = SharedPreferencesStorePlatform.instance;
      SharedPreferencesStorePlatform.instance = _FailingPreferences();
      try {
        await expectLater(library.setHidden(entry, true), throwsStateError);
        expect(library.hidden.contains(entry.key), false);
        library.hidden.add(entry.key);
        await expectLater(
          library.restoreHidden(entry.key),
          throwsStateError,
        );
        expect(library.hidden.contains(entry.key), true);
      } finally {
        SharedPreferencesStorePlatform.instance = previousStore;
        library.dispose();
      }
    },
  );
  test(
    'backup round trip includes sound settings and every stock preview wallpaper',
    () async {
      SharedPreferences.setMockInitialValues({
        'preview_wallpaper': 'assets/wallpapers/dolomites.jpg',
        'app_key_click_enabled': false,
        'navigation_sound_volume': .65,
      });

      final preferences = await SharedPreferences.getInstance();
      final backup = LauncherBackup.parse(
        LauncherBackup(LauncherBackup.preferencesFrom(preferences), {
          'categories': [],
          'hidden': [],
        }).encode(),
      );
      await preferences.setDouble('navigation_sound_volume', .1);
      await LauncherBackup.applyPreferences(preferences, backup.preferences);
      expect(preferences.getDouble('navigation_sound_volume'), .65);
      expect(preferences.getBool('app_key_click_enabled'), false);
      expect(
        preferences.getString('preview_wallpaper'),
        'assets/wallpapers/dolomites.jpg',
      );
    },
  );
}
