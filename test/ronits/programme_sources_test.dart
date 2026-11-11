import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:luma/models/watch_next_item.dart';
import 'package:luma/ronits/programme_library.dart';
import 'package:luma/ronits/programme_browser.dart';

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
  testWidgets('source picker stays open and filters the shelf live', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final library = ProgrammeLibrary.shared;
    await tester.runAsync(library.ready);
    library.disabledSources.clear();
    library.hidden.clear();
    library.saved.clear();
    library.replace([
      entry(91, 'Source test Netflix', 'Netflix'),
      entry(92, 'Source test Prime', 'Prime Video'),
    ]);
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
    await tester.tap(find.byKey(const ValueKey('programme-source-Netflix')));
    await tester.runAsync(() async {
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();
    expect(find.text('From your apps · Sources'), findsOneWidget);
    expect(library.sourceEnabled(library.source.first), false);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Source test Netflix'), findsNothing);
    expect(find.text('Source test Prime'), findsOneWidget);
    expect(tester.takeException(), isNull);
    library.disabledSources.clear();
    await tester.pumpWidget(const SizedBox());
  });
}
