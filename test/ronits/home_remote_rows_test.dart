import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:luma/preview_main.dart';
import 'package:luma/ronits/programme_rail.dart';

void main() {
  for (final viewportWidth in [960.0, 720.0]) {
    testWidgets(
      'remote stays in rows and reveals programmes below a large clock at $viewportWidth',
      (tester) async {
        tester.view.physicalSize = Size(viewportWidth, 540);
        tester.view.devicePixelRatio = 1;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });
        SharedPreferences.setMockInitialValues({
          'minimal_background': 'glass',
          'home_wallpaper_accent': false,
          'home_clock_style': 'analog',
          'home_clock_size': 'large',
        });
        await tester.pumpWidget(
          PreviewApp(preferences: await SharedPreferences.getInstance()),
        );
        await tester.pumpAndSettle();
        Future<void> key(LogicalKeyboardKey key) async {
          await tester.sendKeyEvent(key);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }

        ProgrammeCard? selectedCard() => FocusManager
            .instance
            .primaryFocus
            ?.context
            ?.findAncestorWidgetOfExactType<ProgrammeCard>();
        // Long runs of Right must stay in favourites, including its Add button.
        for (var i = 0; i < 12; i++) {
          await key(LogicalKeyboardKey.arrowRight);
          expect(selectedCard(), isNull);
          expect(
            FocusManager.instance.primaryFocus?.debugLabel,
            isNot(contains('settings')),
          );
        }
        // Return through every favourite after the rail has scrolled right.
        for (var i = 0; i < 12; i++) {
          await key(LogicalKeyboardKey.arrowLeft);
          final visible = FocusManager.instance.primaryFocus!.rect;
          expect(
            visible.left,
            greaterThanOrEqualTo(0),
            reason: 'Left must reveal the selected dock app',
          );
          expect(visible.right, lessThanOrEqualTo(viewportWidth));
        }
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'First home app',
        );
        for (var i = 0; i < 12; i++) {
          await key(LogicalKeyboardKey.arrowRight);
        }
        final end = FocusManager.instance.primaryFocus;
        expect(end?.debugLabel, 'Add dock apps');
        await key(LogicalKeyboardKey.arrowLeft);
        expect(FocusManager.instance.primaryFocus?.debugLabel, 'Last dock app');
        await key(LogicalKeyboardKey.arrowRight);
        expect(FocusManager.instance.primaryFocus, same(end));
        await key(LogicalKeyboardKey.arrowRight);
        expect(FocusManager.instance.primaryFocus, same(end));
        await key(LogicalKeyboardKey.arrowDown);
        expect(
          selectedCard(),
          isNotNull,
          reason: 'Down enters a programme directly',
        );
        final card = selectedCard()!;
        final rect = FocusManager.instance.primaryFocus!.rect;
        expect(rect.top, greaterThanOrEqualTo(0));
        expect(rect.bottom, lessThanOrEqualTo(540));
        final clock = find.byKey(const ValueKey('home-clock-pill'));
        if (clock.evaluate().isNotEmpty) {
          expect(
            tester.getRect(clock).bottom,
            lessThanOrEqualTo(0),
            reason: 'Clock scrolls away',
          );
        }
        final firstTitle = card.title;
        await key(LogicalKeyboardKey.arrowRight);
        expect(selectedCard(), isNotNull);
        expect(selectedCard()!.title, isNot(firstTitle));
        for (var i = 0; i < 15; i++) {
          await key(LogicalKeyboardKey.arrowRight);
          expect(selectedCard(), isNotNull);
          final visible = FocusManager.instance.primaryFocus!.rect;
          expect(visible.top, greaterThanOrEqualTo(0));
          expect(visible.bottom, lessThanOrEqualTo(540));
          expect(visible.left, greaterThanOrEqualTo(0));
          expect(visible.right, lessThanOrEqualTo(viewportWidth));
        }
        // Programmes are the last Home row: Down and Right at the end keep
        // the remote on the focused card, which stays on screen.
        final lastCard = FocusManager.instance.primaryFocus;
        await key(LogicalKeyboardKey.arrowDown);
        expect(FocusManager.instance.primaryFocus, same(lastCard));
        expect(selectedCard(), isNotNull);
        final lastRect = FocusManager.instance.primaryFocus!.rect;
        expect(lastRect.top, greaterThanOrEqualTo(0));
        expect(lastRect.bottom, lessThanOrEqualTo(540));
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
