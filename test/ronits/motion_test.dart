import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/ronits/motion.dart';
import 'package:luma/ronits/programme_rail.dart';

void main() {
  testWidgets('programme focus zoom interpolates and respects reduced motion', (
    tester,
  ) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    for (final reduced in [false, true]) {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: reduced),
            child: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 292,
                  height: 210,
                  child: ProgrammeCard(
                    title: 'Focus sample',
                    focusNode: focus,
                    onPressed: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final zoom = find.descendant(
        of: find.byType(ProgrammeCard),
        matching: find.byWidgetPredicate(
          (widget) => widget is Transform && widget.transform.entry(0, 0) != 1,
        ),
      );
      focus.requestFocus();
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      if (reduced) {
        expect(zoom, findsNothing);
      } else {
        final scale = tester.widget<Transform>(zoom).transform.entry(0, 0);
        expect(scale, greaterThan(1));
        expect(scale, lessThan(1.05));
        await tester.pumpAndSettle();
        expect(
          tester.widget<Transform>(zoom).transform.entry(0, 0),
          closeTo(1.05, .0001),
        );
      }
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets(
    'panel slides on opening and closing without fading or live blur',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showLumaDialog<void>(
                context: context,
                fromSide: true,
                builder: (context) => Dialog(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close panel'),
                  ),
                ),
              ),
              child: const Text('Open panel'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open panel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      Transform slide() => tester.widget<Transform>(
        find.byKey(const ValueKey('menu-slide-transform')),
      );
      final opening = slide().transform.entry(0, 3);
      expect(opening, greaterThan(0));
      expect(opening, lessThan(24));
      final menu = find.byType(MenuSlideTransition);
      expect(
        find.descendant(of: menu, matching: find.byType(FadeTransition)),
        findsNothing,
      );
      expect(
        find.descendant(of: menu, matching: find.byType(ImageFiltered)),
        findsNothing,
      );
      expect(
        find.descendant(of: menu, matching: find.byType(Opacity)),
        findsNothing,
      );
      await tester.pumpAndSettle();
      expect(slide().transform.entry(0, 3), 0);
      await tester.tap(find.text('Close panel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(slide().transform.entry(0, 3), greaterThan(0));
      expect(find.text('Close panel'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.text('Close panel'), findsNothing);
    },
  );

  testWidgets('Back during opening reverses without a position jump', (
    tester,
  ) async {
    final controller = AnimationController(
      vsync: tester,
      duration: const Duration(milliseconds: 180),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: MenuSlideTransition(
          animation: controller,
          child: const SizedBox(width: 200, height: 100),
        ),
      ),
    );
    controller.value = .4;
    await tester.pump();
    double position() => tester
        .widget<Transform>(find.byKey(const ValueKey('menu-slide-transform')))
        .transform
        .entry(1, 3);
    final before = position();
    controller.reverse();
    await tester.pump();
    expect(position(), closeTo(before, .001));
    await tester.pump(const Duration(milliseconds: 40));
    expect(position(), greaterThan(before));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('system reduced motion skips panel transition', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Builder(
            builder: (context) => TextButton(
              onPressed: () => showLumaDialog<void>(
                context: context,
                builder: (_) => const Dialog(child: Text('Instant panel')),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    tester
        .widget<TextButton>(find.widgetWithText(TextButton, 'Open'))
        .onPressed!();
    await tester.pump();
    await tester.pump();
    expect(find.text('Instant panel'), findsOneWidget);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('wheel scrolling eases and reduced motion scrolls immediately', (
    tester,
  ) async {
    final controller = LumaScrollController();
    await tester.pumpWidget(
      MaterialApp(
        home: ListView.builder(
          controller: controller,
          itemExtent: 80,
          itemCount: 50,
          itemBuilder: (_, i) => Text('App $i'),
        ),
      ),
    );
    controller.position.pointerScroll(240);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 70));
    expect(controller.offset, greaterThan(0));
    expect(controller.offset, lessThan(240));
    await tester.pumpAndSettle();
    expect(controller.offset, closeTo(240, .1));
    controller.reducedMotion = true;
    controller.position.pointerScroll(120);
    expect(controller.offset, closeTo(360, .1));
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}
