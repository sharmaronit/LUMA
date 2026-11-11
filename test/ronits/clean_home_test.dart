import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:luma/preview_main.dart';
import 'package:luma/ronits/programme_rail.dart';
import 'package:luma/ronits/programme_library.dart';

void main() {
  testWidgets(
    'dock fades and focus labels follow the remote',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      SharedPreferences.setMockInitialValues({
        'minimal_background': 'glass',
        'home_wallpaper_accent': false,
      });
      await tester.pumpWidget(
        PreviewApp(preferences: await SharedPreferences.getInstance()),
      );
      await tester.pumpAndSettle();
      final opacity = find.byKey(const ValueKey('home-dock-opacity'));
      expect(tester.widget<Opacity>(opacity).opacity, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('utility-label-Search apps')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('utility-label-Voice search')),
        findsNothing,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('utility-label-Search apps')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('utility-label-Voice search')),
        findsOneWidget,
      );
      final scroll = tester
          .widget<CustomScrollView>(
            find.byKey(const ValueKey('minimal-scroll')),
          )
          .controller!;
      scroll.jumpTo(80);
      await tester.pumpAndSettle();
      expect(tester.widget<Opacity>(opacity).opacity, closeTo(.5, .01));
      scroll.jumpTo(240);
      await tester.pumpAndSettle();
      expect(tester.widget<Opacity>(opacity).opacity, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('content has one filter entry and hides an empty watchlist', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    SharedPreferences.setMockInitialValues({
      'minimal_background': 'glass',
      'home_wallpaper_accent': false,
    });
    ProgrammeLibrary.shared.saved.clear();
    await tester.pumpWidget(
      PreviewApp(preferences: await SharedPreferences.getInstance()),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('programme-filter-button')),
      findsOneWidget,
    );
    expect(find.byType(ChoiceChip), findsNothing);
    expect(
      tester.getTopLeft(find.text('From your apps')).dx,
      closeTo(tester.getTopLeft(find.byType(ProgrammeCard).first).dx, 1),
    );
    await tester.tap(find.byKey(const ValueKey('programme-filter-button')));
    await tester.pumpAndSettle();
    expect(find.text('Watchlist (0)'), findsNothing);
    expect(find.text('Netflix').last, findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('only unfinished supported shows get a progress line', (
    tester,
  ) async {
    for (final progress in <double?>[null, 0, .42, 1]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 360,
              height: 246,
              child: ProgrammeCard(
                title: 'Show',
                progress: progress,
                onPressed: () {},
              ),
            ),
          ),
        ),
      );
      expect(
        find.byType(LinearProgressIndicator),
        progress == .42 ? findsOneWidget : findsNothing,
      );
      if (progress == .42)
        expect(
          tester
              .widget<LinearProgressIndicator>(
                find.byType(LinearProgressIndicator),
              )
              .semanticsValue,
          '42',
        );
      await tester.pumpWidget(const SizedBox());
    }
  });
}
