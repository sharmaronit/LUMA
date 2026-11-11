import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:luma/preview_main.dart';
import 'package:luma/models/watch_next_item.dart';
import 'package:luma/ronits/launcher_home.dart';
import 'package:luma/ronits/programme_library.dart';
import 'package:luma/ronits/programme_browser.dart';
import 'package:luma/ronits/font_styles.dart';
import 'package:luma/ronits/app_customization.dart';
import 'package:luma/ronits/launcher_backup.dart';
import 'package:luma/ronits/focus_feedback.dart';

void tv(WidgetTester tester) {
  tester.view.physicalSize = const Size(960, 540);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'installed streaming apps are selectable before sharing titles; settings persist when cards arrive',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final library = ProgrammeLibrary.shared;
      await tester.runAsync(library.ready);
      library.disabledSources.clear();
      library.hidden.clear();
      library.saved.clear();
      library.registerSources({
        'com.netflix.ninja': 'Netflix',
        'com.amazon.amazonvideo.livingroom': 'Prime Video',
      });
      library.replace([]);
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: ProgrammeShelf())),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('programme-filter-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('programme-sources-button')));
      await tester.runAsync(() async {
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pumpAndSettle();
      expect(find.text('No shared titles yet'), findsNWidgets(2));
      await tester.tap(
        find.byKey(const ValueKey('programme-source-com.netflix.ninja')),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pumpAndSettle();
      expect(library.disabledSources, contains('com.netflix.ninja'));
      library.replace([
        ProgrammeEntry(
          WatchNextItem(
            id: 42,
            title: 'Shared episode',
            packageName: 'com.netflix.ninja',
            contentId: '42',
          ),
          'Netflix',
        ),
      ]);
      await tester.pumpAndSettle();
      expect(find.text('1 shared title'), findsOneWidget);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.text('Shared episode'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('programme-filter-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('programme-sources-button')));
      await tester.runAsync(() async {
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('programme-source-com.netflix.ninja')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pumpAndSettle();
      expect(find.text('Shared episode'), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getStringList('programme_disabled_sources_v1'),
        isNot(contains('com.netflix.ninja')),
      );
      await tester.pumpWidget(const SizedBox());
      library.disabledSources.clear();
      library.registerSources({});
      library.replace([]);
    },
  );
  testWidgets(
    'permission and refresh controls stay available with no programme cards',
    (tester) async {
      final library = ProgrammeLibrary.shared;
      var grants = 0, refreshes = 0;
      library.registerSources({'tv.video': 'Video app'}, allowed: false);
      library.requestSourceAccess = () async {
        grants++;
      };
      library.refreshSources = () async {
        refreshes++;
        library.registerSources({'tv.video': 'Video app'});
      };
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showProgrammeSources(context),
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.runAsync(() async {
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pumpAndSettle();
      expect(find.text('TV content access required'), findsOneWidget);
      await tester.tap(find.text('Allow content access'));
      await tester.pumpAndSettle();
      expect(grants, 1);
      await tester.tap(find.text('Refresh'));
      await tester.pumpAndSettle();
      expect(refreshes, 1);
      expect(find.text('No shared titles yet'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      library.registerSources({});
      library.refreshSources = null;
      library.requestSourceAccess = null;
    },
  );
  testWidgets(
    'ten dock apps retain card size and remote navigation reveals the last app',
    (tester) async {
      tv(tester);
      final ids = [
        'youtube',
        'netflix',
        'jiohotstar',
        'primevideo',
        'sonyliv',
        'zee5',
        'jiotv',
        'spotify',
        'plex',
        'vlc',
      ];
      SharedPreferences.setMockInitialValues({
        'preview_favorites': ids,
        'reduce_motion': true,
        'home_show_watch': false,
        'home_remember_selection': false,
      });
      await tester.pumpWidget(
        PreviewApp(preferences: await SharedPreferences.getInstance()),
      );
      await tester.pumpAndSettle();
      final home = tester.widget<LauncherHome>(find.byType(LauncherHome));
      final actual = home.favorites;
      expect(actual.length, 10);
      final first = find.byKey(ValueKey('favorite-${actual.first.id}'));
      final last = find.byKey(ValueKey('favorite-${actual.last.id}'));
      final width = tester.getSize(first).width;
      expect(tester.getSize(last).width, closeTo(width, .01));
      for (var i = 1; i < actual.length; i++)
        await press(tester, LogicalKeyboardKey.arrowRight);
      expect(tester.getRect(last).right, lessThanOrEqualTo(960));
      expect(tester.getRect(last).left, greaterThanOrEqualTo(0));
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'Last dock app');
      await tester.tap(find.byTooltip('All apps'));
      await tester.pumpAndSettle();
      for (final app in actual) {
        expect(find.byKey(ValueKey(app.id)), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'row tint stays within its own row during selection and scrolling',
    (tester) async {
      final scroll = ScrollController();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 360,
              height: 180,
              child: FocusHighlightLayer(
                menu: true,
                child: ListView(
                  controller: scroll,
                  children: [
                    for (var i = 0; i < 5; i++)
                      TvMenuRow(
                        key: ValueKey('row-$i'),
                        autofocus: i == 0,
                        title: 'Option $i',
                        subtitle: i == 0 ? 'A taller first row' : null,
                        onPressed: () {},
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump(const Duration(milliseconds: 40));
      final row = find.byKey(const ValueKey('row-1'));
      final tint = find.descendant(
        of: row,
        matching: find.byKey(const ValueKey('menu-row-focus-tint')),
      );
      expect(
        tester.widget<AnimatedContainer>(tint).clipBehavior,
        Clip.hardEdge,
      );
      final bounds = tester.getRect(row), paint = tester.getRect(tint);
      expect(bounds.inflate(.1).contains(paint.topLeft), true);
      expect(bounds.inflate(.1).contains(paint.bottomRight), true);
      expect(find.byType(AnimatedPositioned), findsNothing);
      final previous = tester.widget<AnimatedContainer>(
        find.descendant(
          of: find.byKey(const ValueKey('row-0')),
          matching: find.byKey(const ValueKey('menu-row-focus-tint')),
        ),
      );
      expect((previous.decoration as BoxDecoration).color, Colors.transparent);
      scroll.jumpTo(30);
      await tester.pumpAndSettle();
      expect(tester.getRect(tint).size, tester.getRect(row).size);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      scroll.dispose();
    },
  );
  testWidgets(
    'font selection applies globally without closing its menu and survives restart',
    (tester) async {
      tv(tester);
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
        find.byKey(const ValueKey('settings-category-Appearance')),
      );
      await tester.pumpAndSettle();
      final setting = find.byKey(const ValueKey('setting-font-style'));
      await tester.ensureVisible(setting);
      await tester.tap(setting);
      await tester.pumpAndSettle();
      await press(tester, LogicalKeyboardKey.arrowDown);
      await press(tester, LogicalKeyboardKey.select);
      expect(prefs.getString(AppCustomization.fontKey), 'rounded');
      expect(find.byKey(const ValueKey('font-style-rounded')), findsOneWidget);
      final theme = Theme.of(
        tester.element(find.byKey(const ValueKey('font-style-rounded'))),
      );
      expect(theme.textTheme.bodyMedium?.fontFamily, 'Nunito');
      expect(
        theme.textButtonTheme.style?.textStyle?.resolve({})?.fontFamily,
        'Nunito',
      );
      expect(launcherFont('elegant').familyLabel, 'Plus Jakarta Sans');
      expect(launcherFont('soft').familyLabel, 'DM Sans');
      expect(launcherFont('current').familyLabel, 'Inter');
      for (final font in launcherFonts) {
        // The list is longer than the dialog; scroll each row into view.
        await tester.ensureVisible(
          find.byKey(ValueKey('font-style-${font.id}')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(ValueKey('font-style-${font.id}')));
        await tester.pumpAndSettle();
        expect(
          Theme.of(
            tester.element(find.byKey(ValueKey('font-style-${font.id}'))),
          ).textTheme.bodyMedium?.fontFamily,
          font.family,
        );
      }
      await tester.ensureVisible(
        find.byKey(const ValueKey('font-style-rounded')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('font-style-rounded')));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(PreviewApp(preferences: prefs));
      await tester.pumpAndSettle();
      expect(
        Theme.of(
          tester.element(find.byType(LauncherHome)),
        ).textTheme.bodyMedium?.fontFamily,
        'Nunito',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  test(
    'all font choices are offline and the font preference survives backup',
    () async {
      SharedPreferences.setMockInitialValues({
        AppCustomization.fontKey: 'classic',
      });
      final prefs = await SharedPreferences.getInstance();
      final backup = LauncherBackup.parse(
        LauncherBackup(LauncherBackup.preferencesFrom(prefs), {
          'categories': [],
          'hidden': [],
        }).encode(),
      );
      expect(backup.preferences[AppCustomization.fontKey], 'classic');
      for (final font in launcherFonts.skip(1)) {
        expect(
          File('assets/fonts/${font.family}-Variable.ttf').existsSync(),
          true,
        );
        expect(
          File(
            'assets/fonts/${font.family.toUpperCase()}-OFL.txt',
          ).readAsStringSync(),
          contains('SIL OPEN FONT LICENSE'),
        );
      }
      final store = AppCustomization(prefs);
      await store.load();
      expect(store.fontStyle, 'classic');
      await expectLater(store.setFontStyle('unknown'), throwsArgumentError);
      store.dispose();
    },
  );
}
