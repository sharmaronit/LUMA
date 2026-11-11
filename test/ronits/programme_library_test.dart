import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:luma/models/watch_next_item.dart';
import 'package:luma/ronits/programme_library.dart';
import 'package:luma/ronits/programme_browser.dart';
import 'package:luma/ronits/programme_rail.dart';
import 'package:luma/preview_main.dart';

ProgrammeEntry entry(int id, String title, String provider) => ProgrammeEntry(
  WatchNextItem(
    id: id,
    title: title,
    packageName: provider,
    contentId: 'episode-$id',
    intentUri: 'intent://episode-$id',
    description: 'Episode $id',
    progressPercent: 42,
  ),
  provider,
);

void main() {
  test(
    'app sources persist independently of saved titles and search',
    () async {
      SharedPreferences.setMockInitialValues({});
      final library = ProgrammeLibrary();
      final netflix = entry(1, 'Valley', 'Netflix');
      final prime = entry(2, 'Ocean', 'Prime Video');
      library.replace([netflix, prime]);
      await library.setSourceEnabled('Netflix', false);
      expect(library.sourceEnabled(netflix), false);
      expect(library.sourceEnabled(prime), true);
      expect(library.search('Valley'), hasLength(1));
      final restarted = ProgrammeLibrary();
      await restarted.ready();
      expect(restarted.sourceEnabled(netflix), false);
      await restarted.setSourceEnabled('Netflix', true);
      final restored = ProgrammeLibrary();
      await restored.ready();
      expect(restored.sourceEnabled(netflix), true);
      library.dispose();
      restarted.dispose();
      restored.dispose();
    },
  );

  test(
    'watchlist and hiding survive restart, Undo restores, refreshed content deduplicates search',
    () async {
      SharedPreferences.setMockInitialValues({});
      final first = ProgrammeLibrary();
      await first.ready();
      final a = entry(1, 'Valley', 'Netflix');
      final b = entry(2, 'Ocean', 'Prime Video');
      first.replace([a, b]);
      await first.toggleSaved(a);
      await first.setHidden(b, true);
      final restarted = ProgrammeLibrary();
      await restarted.ready();
      restarted.replace([a, b]);
      expect(restarted.saved[a.key]!.item.intentUri, 'intent://episode-1');
      expect(restarted.visible.map((e) => e.item.title), ['Valley']);
      expect(restarted.search('netflix').length, 1);
      expect(restarted.search('ocean'), isEmpty);
      await restarted.restoreHidden(b.key);
      expect(restarted.search('ocean').single.key, b.key);
      await restarted.toggleSaved(a);
      final third = ProgrammeLibrary();
      await third.ready();
      expect(third.saved, isEmpty);
      expect(third.hidden, isEmpty);
      first.dispose();
      restarted.dispose();
      third.dispose();
    },
  );

  test('malformed saved entries do not discard valid entries', () async {
    final a = entry(3, 'Peaks', 'Prime Video');
    SharedPreferences.setMockInitialValues({
      'programme_watchlist_v1': ['invalid', jsonEncode(a.toMap())],
    });
    final library = ProgrammeLibrary();
    await library.ready();
    expect(library.saved.keys, [a.key]);
    library.dispose();
  });

  testWidgets(
    'remote short press plays; held Select opens options without playing',
    (tester) async {
      var plays = 0, options = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 292,
              height: 210,
              child: ProgrammeCard(
                title: 'Remote programme',
                onPressed: () => plays++,
                onOptions: () => options++,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final button = tester.widget<TextButton>(find.byType(TextButton));
      button.focusNode!.requestFocus();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(plays, 1);
      expect(options, 0);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
      await tester.pump(const Duration(milliseconds: 700));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(plays, 1);
      expect(options, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
      await tester.pumpAndSettle();
      expect(options, 2);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'provider filters, watchlist, details, hide, Undo and search work in shared preview',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      SharedPreferences.setMockInitialValues({'home_wallpaper_accent': false});
      final library = ProgrammeLibrary.shared;
      await library.ready();
      library.saved.clear();
      library.hidden.clear();
      await tester.pumpWidget(
        PreviewApp(preferences: await SharedPreferences.getInstance()),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      final firstButton = tester.widget<TextButton>(
        find.descendant(
          of: find.byType(ProgrammeCard).first,
          matching: find.byType(TextButton),
        ),
      );
      expect(firstButton.focusNode!.hasFocus, true);
      await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
      await tester.pumpAndSettle();
      expect(find.text('Save to watchlist'), findsOneWidget);
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextButton>(
              find.byKey(const ValueKey('programme-filter-button')),
            )
            .focusNode!
            .hasFocus,
        true,
      );
      await tester.tap(find.byKey(const ValueKey('programme-filter-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Prime Video').last);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      final filteredButton = tester.widget<TextButton>(
        find.descendant(
          of: find.byType(ProgrammeCard).first,
          matching: find.byType(TextButton),
        ),
      );
      expect(filteredButton.focusNode!.hasFocus, true);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('programme-filter-button')));
      await tester.pumpAndSettle();
      final filter = find.text('Netflix').last;
      await tester.ensureVisible(filter);
      await tester.tap(filter);
      await tester.pumpAndSettle();
      expect(find.text('Fallout'), findsNothing);
      final card = find.ancestor(
        of: find.text('Wednesday'),
        matching: find.byType(ProgrammeCard),
      );
      await tester.longPress(card);
      await tester.pumpAndSettle();
      expect(find.text('Save to watchlist'), findsOneWidget);
      await tester.tap(find.text('Save to watchlist'));
      await tester.pumpAndSettle();
      expect(library.saved.length, 1);
      expect(find.byType(ProgrammeDetails), findsOneWidget);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Promotional artwork preview.'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('More options'));
      await tester.tap(find.text('More options'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Hide title'));
      await tester.tap(find.text('Hide title'));
      await tester.pumpAndSettle();
      expect(library.hidden.length, 1);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(library.hidden, isEmpty);
      await tester.tap(find.byKey(const ValueKey('programme-filter-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Watchlist (1)'));
      await tester.pumpAndSettle();
      expect(find.text('Wednesday'), findsOneWidget);
      expect(find.text('ONE PIECE'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Search apps'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Wednesday');
      await tester.pumpAndSettle();
      expect(find.text('Movies & shows'), findsOneWidget);
      expect(find.byType(LibraryProgrammeCard), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      library.saved.clear();
      library.hidden.clear();
    },
  );
}
