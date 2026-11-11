import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/ronits/launcher_home.dart';

void main() {
  testWidgets('dock picker keeps remote selection visible in both directions', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DockAppPicker(
            apps: List.generate(
              20,
              (i) => LauncherAppItem(id: '$i', name: 'App $i'),
            ),
            favorites: const {},
            onToggle: (_) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    Future<void> move(LogicalKeyboardKey key, int index) async {
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'Dock choice $index',
      );
      final row = tester.getRect(find.byKey(ValueKey('dock-choice-$index')));
      final viewport = tester.getRect(find.byType(ListView));
      expect(row.top, greaterThanOrEqualTo(viewport.top - .5));
      expect(row.bottom, lessThanOrEqualTo(viewport.bottom + .5));
    }

    for (var i = 1; i < 16; i++) {
      await move(LogicalKeyboardKey.arrowDown, i);
    }
    for (var i = 14; i >= 0; i--) {
      await move(LogicalKeyboardKey.arrowUp, i);
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'Search dock apps');
    await move(LogicalKeyboardKey.arrowDown, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
