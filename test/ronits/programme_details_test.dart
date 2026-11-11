import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:luma/models/watch_next_item.dart';
import 'package:luma/ronits/programme_browser.dart';
import 'package:luma/ronits/programme_library.dart';

void main() {
  testWidgets(
    'details show progress, save feedback and an app fallback after failed playback',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final library = ProgrammeLibrary.shared;
      await library.ready();
      const provider = 'test.provider';
      final entry = ProgrammeEntry(
        WatchNextItem(
          id: 72,
          title: 'A programme',
          packageName: provider,
          description: 'A useful description',
          progressPercent: 35,
        ),
        'Provider',
      );
      final calls = <bool>[];
      library.launch = (_, appOnly) async {
        calls.add(appOnly);
        return appOnly;
      };
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ProgrammeDetails(entry: entry)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('35% watched'), findsOneWidget);
      expect(find.text('A useful description'), findsOneWidget);
      await tester.ensureVisible(find.text('Resume'));
      await tester.tap(find.text('Resume'));
      await tester.pumpAndSettle();
      expect(
        find.text('This title could not open. Try Open streaming app.'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('Open streaming app'));
      await tester.tap(find.text('Open streaming app'));
      await tester.pumpAndSettle();
      expect(calls, [false, true]);
      await tester.ensureVisible(find.text('Save to watchlist'));
      await tester.tap(find.text('Save to watchlist'));
      await tester.pumpAndSettle();
      expect(find.text('Saved to watchlist'), findsOneWidget);
      expect(library.saved.containsKey(entry.key), true);
      expect(find.text('Remove from watchlist'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
