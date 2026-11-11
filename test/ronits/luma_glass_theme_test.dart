import 'package:flutter/material.dart';
import 'package:luma/ronits/motion.dart';
import 'package:provider/provider.dart';
import 'package:mockito/mockito.dart';
import 'package:luma/providers/wallpaper_service.dart';
import 'package:luma/ronits/shared_blur_cache.dart';
import 'package:luma/widgets/cached_blur_backdrop.dart';
import 'package:luma/gradients.dart';
import '../mocks.mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:luma/preview_main.dart';
import 'package:luma/providers/settings_service.dart';
import 'package:luma/ronits/focus_feedback.dart';
import 'package:luma/ronits/launcher_backup.dart';
import 'package:luma/ronits/glass_surface.dart';
import 'package:luma/ronits/luma_glass_theme.dart';

class _PaintProbe extends CustomPainter {
  int paints = 0;
  @override
  void paint(Canvas canvas, Size size) {
    paints++;
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.blue);
  }

  @override
  bool shouldRepaint(_PaintProbe oldDelegate) => false;
}

class _CachedWallpaper extends MockWallpaperService {
  @override
  final sharedBlurCache = SharedBlurCache();
}

void main() {
  testWidgets(
    'both glass finishes use the same cached blur at either quality setting',
    (tester) async {
      for (final economy in [false, true]) {
        for (final panel in [false, true]) {
          double? cachedSigma;
          double? cachedSaturation;
          Widget scene(String theme) => MaterialApp(
            home: MenuAppearanceScope(
              mode: LauncherMaterial.minimal,
              minimalBackground: theme,
              economyGlass: economy,
              blurBuilder: (child, sigma, saturation) {
                cachedSigma = sigma;
                cachedSaturation = saturation;
                return child;
              },
              child: LumaGlassPanel(
                cachedBlur: panel,
                child: const SizedBox(width: 200, height: 100),
              ),
            ),
          );
          await tester.pumpWidget(scene('glass'));
          expect(cachedSigma, isNotNull);
          final expected = (cachedSigma, cachedSaturation);
          cachedSigma = null;
          cachedSaturation = null;
          await tester.pumpWidget(scene('glass-real'));
          expect((cachedSigma, cachedSaturation), expected);
          expect(find.byType(BackdropFilter), findsNothing);
        }
      }
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('Real glass uses prepared wallpaper without live filters', (
    tester,
  ) async {
    var cachedCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: MenuAppearanceScope(
          mode: LauncherMaterial.minimal,
          minimalBackground: 'glass-real',
          economyGlass: true,
          blurBuilder: (child, sigma, saturation) {
            cachedCalls++;
            return child;
          },
          child: const LumaGlassPanel(child: SizedBox(width: 200, height: 100)),
        ),
      ),
    );
    expect(find.byType(BackdropFilter), findsNothing);
    expect(cachedCalls, 1);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('focus animation does not repaint the cached glass background', (
    tester,
  ) async {
    final background = _PaintProbe();
    final position = ValueNotifier<double>(0);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MenuAppearanceScope(
            mode: LauncherMaterial.minimal,
            minimalBackground: 'glass',
            blurBuilder: (child, sigma, saturation) =>
                CustomPaint(painter: background, child: child),
            child: LumaGlassPanel(
              child: SizedBox(
                width: 400,
                height: 200,
                child: ValueListenableBuilder<double>(
                  valueListenable: position,
                  builder: (_, value, child) => Transform.translate(
                    offset: Offset(value, 0),
                    child: child,
                  ),
                  child: const Text('Focused app'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final initial = background.paints;
    expect(initial, greaterThan(0));
    for (var frame = 1; frame <= 12; frame++) {
      position.value = frame.toDouble();
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(background.paints, initial);
    await tester.pumpWidget(const SizedBox());
    position.dispose();
  });

  testWidgets(
    'sliding cached glass does not repaint its texture every route tick',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsService(await SharedPreferences.getInstance());
      final wallpaper = _CachedWallpaper();
      when(wallpaper.wallpaperRevision).thenReturn(0);
      when(wallpaper.wallpaper).thenReturn(null);
      when(wallpaper.wallpaperVideoFile).thenReturn(null);
      when(wallpaper.gradient).thenReturn(LumaGradients.saintPetersburg);
      final paint = _PaintProbe();
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsService>.value(value: settings),
            ChangeNotifierProvider<WallpaperService>.value(value: wallpaper),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () => showLumaDialog<void>(
                  context: context,
                  builder: (_) => Center(
                    child: SizedBox(
                      width: 400,
                      height: 200,
                      child: RepaintBoundary(
                        child: CustomPaint(
                          painter: paint,
                          child: const CachedBlurBackdrop(
                            sigma: 24,
                            child: Text('Glass menu'),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                child: const Text('Open glass'),
              ),
            ),
          ),
        ),
      );
      // Warm the shared wallpaper cache once, then reopen the same surface.
      await tester.tap(find.text('Open glass'));
      await tester.pump();
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
      }
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open glass'));
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));
      final initial = paint.paints;
      expect(initial, greaterThan(0));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(paint.paints, initial);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      wallpaper.sharedBlurCache.dispose();
      settings.dispose();
    },
  );

  testWidgets('scrolling refreshes the cached wallpaper crop', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsService(await SharedPreferences.getInstance());
    final wallpaper = _CachedWallpaper();
    when(wallpaper.wallpaperRevision).thenReturn(0);
    when(wallpaper.wallpaper).thenReturn(null);
    when(wallpaper.wallpaperVideoFile).thenReturn(null);
    when(wallpaper.gradient).thenReturn(LumaGradients.greatWhale);
    final scroll = ScrollController();
    final paint = _PaintProbe();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsService>.value(value: settings),
          ChangeNotifierProvider<WallpaperService>.value(value: wallpaper),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              controller: scroll,
              child: Column(
                children: [
                  const SizedBox(height: 250),
                  SizedBox(
                    width: 400,
                    height: 180,
                    child: RepaintBoundary(
                      child: CustomPaint(
                        painter: paint,
                        child: const CachedBlurBackdrop(
                          sigma: 8,
                          child: SizedBox.expand(),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 800),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    expect(wallpaper.sharedBlurCache.entryCount, 1);
    final initial = paint.paints;
    scroll.jumpTo(100);
    await tester.pumpAndSettle();
    expect(
      paint.paints,
      greaterThan(initial),
      reason: 'A moved glass surface must sample its new wallpaper position',
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    scroll.dispose();
    wallpaper.sharedBlurCache.dispose();
    settings.dispose();
  });

  testWidgets(
    'native cached glass preserves child state and focus when texture arrives',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsService(await SharedPreferences.getInstance());
      final wallpaper = _CachedWallpaper();
      when(wallpaper.wallpaperRevision).thenReturn(0);
      when(wallpaper.wallpaper).thenReturn(null);
      when(wallpaper.wallpaperVideoFile).thenReturn(null);
      when(wallpaper.gradient).thenReturn(LumaGradients.greatWhale);
      final probe = GlobalKey();
      final focus = FocusNode();
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsService>.value(value: settings),
            ChangeNotifierProvider<WallpaperService>.value(value: wallpaper),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 400,
                height: 200,
                child: CachedBlurBackdrop(
                  sigma: 24,
                  child: TextButton(
                    key: probe,
                    autofocus: true,
                    focusNode: focus,
                    onPressed: () {},
                    child: const Text('Selected app'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final original = probe.currentState;
      expect(focus.hasFocus, true);
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
      }
      expect(wallpaper.sharedBlurCache.entryCount, 1);
      expect(probe.currentState, same(original));
      expect(focus.hasFocus, true);
      expect(find.byType(BackdropFilter), findsNothing);
      await tester.pumpWidget(const SizedBox());
      focus.dispose();
      wallpaper.sharedBlurCache.dispose();
      settings.dispose();
    },
  );

  testWidgets(
    'Luma Glass is optional and switches live without replacing Clean',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      SharedPreferences.setMockInitialValues({'home_wallpaper_accent': false});
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(PreviewApp(preferences: prefs));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('luma-glass-panel')), findsNothing);
      await tester.tap(find.byTooltip('Clock'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Luma settings'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('settings-category-Appearance')),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Theme'));
      await tester.tap(find.text('Theme'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('minimal-background-glass')),
      );
      await tester.tap(find.byKey(const ValueKey('minimal-background-glass')));
      await tester.pumpAndSettle();
      expect(prefs.getString('minimal_background'), 'glass');
      expect(find.byKey(const ValueKey('luma-glass-panel')), findsWidgets);
      expect(find.text('Theme'), findsWidgets);
      expect(find.byType(BackdropFilter), findsNothing);
      final homeFrame = tester
          .widgetList<FocusHighlightLayer>(find.byType(FocusHighlightLayer))
          .where((f) => f.cardFocus)
          .single;
      expect(homeFrame.frameAbove, true);
      await tester.ensureVisible(
        find.byKey(const ValueKey('minimal-background-charcoal')),
      );
      await tester.tap(
        find.byKey(const ValueKey('minimal-background-charcoal')),
      );
      await tester.pumpAndSettle();
      expect(prefs.getString('minimal_background'), 'charcoal');
      expect(find.byKey(const ValueKey('luma-glass-panel')), findsNothing);
      expect(find.text('Theme'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  test(
    'native settings and backups preserve Luma Glass as a separate theme',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final settings = SettingsService(prefs);
      await settings.setMinimalBackground('glass');
      expect(settings.minimalBackground, 'glass');
      final backup = LauncherBackup(LauncherBackup.preferencesFrom(prefs), {
        'categories': [],
        'hidden': [],
      });
      final restored = LauncherBackup.parse(backup.encode());
      expect(restored.preferences['minimal_background'], 'glass');
      await settings.setMinimalBackground('charcoal');
      expect(settings.minimalBackground, 'charcoal');
      settings.dispose();
    },
  );
}
