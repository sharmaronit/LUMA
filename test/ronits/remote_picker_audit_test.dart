import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/ronits/launcher_home.dart';
import 'package:luma/ronits/clock_settings.dart';
import 'package:luma/preview_main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('held direction continues moving without activating an app', (
    tester,
  ) async {
    var moves = 0, launches = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 220,
            height: 200,
            child: LauncherTile(
              app: LauncherAppItem(id: 'a', name: 'Alpha'),
              autofocus: true,
              reduceMotion: true,
              onRight: () => moves++,
              onPressed: () => launches++,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(moves, 3);
    expect(launches, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'dock search hands focus to results, including an empty query result',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DockAppPicker(
              apps: [
                LauncherAppItem(id: 'a', name: 'Alpha'),
                LauncherAppItem(id: 'b', name: 'Beta'),
              ],
              favorites: const {},
              onToggle: (_) async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(TextField));
      await tester.enterText(find.byType(TextField), 'Beta');
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'Dock choice b');
      expect(tester.testTextInput.isVisible, false);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'Search dock apps',
      );
      await tester.enterText(find.byType(TextField), 'missing');
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'Dock apps Done');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('clock navigation skips unavailable format control', (
    tester,
  ) async {
    final sizes = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ClockSettings(
            style: 'digital',
            size: '50',
            pattern: 'HH:mm',
            onStyleChanged: (_) {},
            onSizeChanged: sizes.add,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'Clock size slider');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(sizes, ['55']);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'Clock style');
    await tester.pumpWidget(const SizedBox());
  });
}
