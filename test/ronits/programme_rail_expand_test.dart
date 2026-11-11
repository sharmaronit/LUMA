import 'package:luma/ronits/programme_rail.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'compact rail widens the focused card and moves its details onto it',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final first = FocusNode();
      addTearDown(first.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Scaffold(
              body: ProgrammeRail(
                compact: true,
                cardWidth: 246,
                height: 220,
                itemCount: 3,
                itemBuilder: (_, index) => ProgrammeCard(
                  key: ValueKey('card-$index'),
                  focusNode: index == 0 ? first : null,
                  compact: true,
                  title: 'Show $index',
                  provider: 'Netflix',
                  progress: .4,
                  onPressed: () {},
                ),
              ),
            ),
          ),
        ),
      );
      Size art(int index) => tester.getSize(
        find
            .descendant(
              of: find.byKey(ValueKey('card-$index')),
              matching: find.byType(AspectRatio),
            )
            .first,
      );
      final normal = art(0);
      expect(find.byKey(const ValueKey('programme-wide-details')), findsNothing);

      first.requestFocus();
      await tester.pumpAndSettle();
      final wide = art(0);
      expect(wide.width, closeTo(normal.width * 1.6, 1));
      expect(wide.height, closeTo(normal.height, .5));
      expect(
        find.byKey(const ValueKey('programme-wide-details')),
        findsOneWidget,
      );
      // Details are on the artwork, not repeated under it.
      expect(find.text('Show 0'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(art(0).width, closeTo(normal.width, 1));
      expect(art(1).width, closeTo(normal.width * 1.6, 1));
      expect(tester.takeException(), isNull);
    },
  );
}
