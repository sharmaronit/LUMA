import 'dart:ui' as ui;
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:luma/preview_main.dart';
import 'package:luma/ronits/app_customization.dart';
import 'package:luma/ronits/launcher_home.dart';
import 'package:luma/ronits/glass_surface.dart';
import 'package:luma/ronits/focus_feedback.dart';
import 'package:luma/ronits/menu_dialog.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late AppCustomization store;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('luma-artwork-test');
    final old = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(dir.path);
    addTearDown(() async {
      PathProviderPlatform.instance = old;
      await dir.delete(recursive: true);
    });
    SharedPreferences.setMockInitialValues({});
    store = AppCustomization(await SharedPreferences.getInstance());
    await store.load();
  });
  tearDown(() => store.dispose());
  test(
    'shortcuts persist, can be cleared, and cannot take over navigation',
    () async {
      await store.setShortcut('1', 'search');
      await store.setShortcut('Red', 'app:com.netflix.ninja');
      final restored = AppCustomization(await SharedPreferences.getInstance());
      await restored.load();
      expect(restored.actionFor(LogicalKeyboardKey.digit1), 'search');
      expect(
        restored.actionFor(LogicalKeyboardKey.colorF0Red),
        'app:com.netflix.ninja',
      );
      await expectLater(store.setShortcut('Home', 'apps'), throwsArgumentError);
      await expectLater(
        store.setShortcut('1', 'bad-action'),
        throwsArgumentError,
      );
      await store.setShortcut('1', null);
      expect(store.actionFor(LogicalKeyboardKey.digit1), isNull);
      restored.dispose();
    },
  );
  test('malformed saved settings are ignored', () async {
    await store.preferences.setString(AppCustomization.shortcutsKey, '{bad');
    await store.preferences.setString(
      AppCustomization.artworkKey,
      jsonEncode({'a': 'pack:../../file', 'b': 4}),
    );
    final restored = AppCustomization(store.preferences);
    await restored.load();
    expect(restored.shortcuts, isEmpty);
    expect(restored.artwork, isEmpty);
    restored.dispose();
  });
  test(
    'custom images persist, same-app replacement refreshes, and reset removes files',
    () async {
      final first = await File('assets/tv-icons/netflix.png').readAsBytes();
      final second = await File('assets/tv-icons/youtube.png').readAsBytes();
      await store.setArtwork('a', 'custom', bytes: first);
      final image1 = await store.image('a') as MemoryImage;
      final codec = await ui.instantiateImageCodec(image1.bytes);
      final frame = await codec.getNextFrame();
      expect(frame.image.width, lessThanOrEqualTo(640));
      expect(frame.image.height, lessThanOrEqualTo(360));
      frame.image.dispose();
      codec.dispose();
      await store.setArtwork('a', 'custom', bytes: second);
      final image2 = await store.image('a') as MemoryImage;
      expect(image2.bytes, isNot(orderedEquals(image1.bytes)));
      final restored = AppCustomization(store.preferences);
      await restored.load();
      expect(
        (await restored.image('a') as MemoryImage).bytes,
        orderedEquals(image2.bytes),
      );
      await expectLater(
        store.setArtwork('a', 'custom', bytes: Uint8List.fromList([0, 1])),
        throwsA(anything),
      );
      expect(store.artwork['a'], 'custom');
      await store.setArtwork('a', null);
      expect(store.artwork['a'], isNull);
      expect(dir.listSync(recursive: true).whereType<File>(), isEmpty);
      restored.dispose();
    },
  );
  testWidgets(
    'artwork can switch between TV pack, installed artwork and automatic',
    (tester) async {
      final fallback = Future<ImageProvider?>.value(
        const AssetImage('assets/tv-icons/netflix.png'),
      );
      await tester.pumpWidget(
        AppCustomizationScope(
          controller: store,
          child: MaterialApp(
            home: AppArtworkBuilder(
              id: 'a',
              future: fallback,
              original: () async =>
                  const AssetImage('assets/tv-icons/youtube.png'),
              builder: (_, snapshot) => snapshot.data == null
                  ? const SizedBox()
                  : Image(image: snapshot.data!),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> expectImage(String? source, String filename) async {
        await tester.runAsync(() => store.setArtwork('a', source));
        await tester.pump();
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        });
        await tester.pumpAndSettle();
        expect(
          (tester.widget<Image>(find.byType(Image)).image as AssetImage)
              .assetName,
          'assets/tv-icons/$filename.png',
        );
      }

      await expectImage('pack:spotify', 'spotify');
      await expectImage('original', 'youtube');
      await expectImage(null, 'netflix');
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'shortcut activates once on hold and does not hijack a dialog or typing',
    (tester) async {
      await store.setShortcut('1', 'app:netflix');
      await store.setShortcut('2', 'search');
      var launches = 0;
      await tester.pumpWidget(
        AppCustomizationScope(
          controller: store,
          child: MaterialApp(
            home: LauncherHome(
              apps: const [LauncherAppItem(id: 'netflix', name: 'Netflix')],
              favorites: const [
                LauncherAppItem(id: 'netflix', name: 'Netflix'),
              ],
              wallpaper: const AssetImage('assets/mountain.jpg'),
              mode: LauncherMaterial.minimal,
              reducedMotion: true,
              preview: true,
              onMaterialChanged: (_) {},
              onLaunch: (_) async {
                launches++;
              },
              onSettings: () {},
              onWifi: () {},
              onManage: () {},
              onFavorite: (_) async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.digit1);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.digit1);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.digit1);
      await tester.pumpAndSettle();
      expect(launches, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      await tester.enterText(find.byType(TextField), '12');
      await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
      await tester.pumpAndSettle();
      expect(launches, 1);
      expect(find.byType(TextField), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('settings assigns shortcuts and app options save TV artwork', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(960, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    SharedPreferences.setMockInitialValues({
      'reduce_motion': true,
      'home_show_watch': false,
    });
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(PreviewApp(preferences: prefs));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Clock'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Luma settings'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('settings-category-Home & Apps')),
    );
    await tester.pumpAndSettle();
    final shortcuts = find.byKey(const ValueKey('setting-remote-shortcuts'));
    await tester.ensureVisible(shortcuts);
    await tester.tap(shortcuts);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('remote-shortcut-1')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(LumaMenuDialog).last,
        matching: find.byType(FocusHighlightLayer),
      ),
      findsOneWidget,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(
      jsonDecode(prefs.getString(AppCustomization.shortcutsKey)!)['1'],
      'search',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('app-artwork-settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('artwork-pack')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(LumaMenuDialog).last,
        matching: find.byType(FocusHighlightLayer),
      ),
      findsOneWidget,
    );
    final card = find.byKey(const ValueKey('artwork-pack-netflix'));
    await tester.ensureVisible(card);
    await tester.tap(card);
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pumpAndSettle();
    expect(
      (jsonDecode(prefs.getString(AppCustomization.artworkKey)!) as Map).values,
      contains('pack:netflix'),
    );
    expect(find.byKey(const ValueKey('artwork-automatic')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
