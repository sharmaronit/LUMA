import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/ronits/programme_rail.dart';
import 'package:luma/ronits/scroll_edge_fade.dart';

void main() {
  testWidgets(
    'non-overflowing content skips the mask and retains focus as overflow changes',
    (tester) async {
      final focus = FocusNode();
      final scroll = ScrollController();
      var extraHeight = 0.0;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 300,
              height: 160,
              child: StatefulBuilder(
                builder: (_, setState) {
                  update = setState;
                  return ScrollEdgeFade(
                    backdropFade: false,
                    child: SingleChildScrollView(
                      controller: scroll,
                      child: Column(
                        children: [
                          TextButton(
                            focusNode: focus,
                            autofocus: true,
                            onPressed: () {},
                            child: const Text('Keep focus'),
                          ),
                          SizedBox(height: extraHeight),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ShaderMask), findsNothing);
      expect(focus.hasPrimaryFocus, true);
      update(() => extraHeight = 400);
      await tester.pumpAndSettle();
      expect(find.byType(ShaderMask), findsOneWidget);
      expect(focus.hasPrimaryFocus, true);
      scroll.jumpTo(80);
      await tester.pumpAndSettle();
      expect(scroll.offset, 80);
      update(() => extraHeight = 0);
      await tester.pumpAndSettle();
      expect(find.byType(ShaderMask), findsNothing);
      expect(focus.hasPrimaryFocus, true);
      await tester.pumpWidget(const SizedBox());
      focus.dispose();
      scroll.dispose();
    },
  );
  testWidgets('focus inside a visible row does not scroll it', (tester) async {
    final nodes = List.generate(4, (_) => FocusNode());
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 800,
            height: 200,
            child: ProgrammeRail(
              cardWidth: 220,
              height: 180,
              itemCount: 4,
              itemBuilder: (_, i) => ProgrammeCard(
                title: 'Visible $i',
                focusNode: nodes[i],
                onPressed: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    nodes[0].requestFocus();
    await tester.pumpAndSettle();
    final row = tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byType(ProgrammeRail),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(row.position.pixels, 0);
    nodes[1].requestFocus();
    await tester.pumpAndSettle();
    expect(row.position.pixels, 0);
    nodes[3].requestFocus();
    await tester.pumpAndSettle();
    expect(row.position.pixels, greaterThan(0));
    await tester.pumpWidget(const SizedBox());
    for (final node in nodes) {
      node.dispose();
    }
  });

  testWidgets(
    'scroll fades follow overflow without resetting the scroll position',
    (tester) async {
      final controller = ScrollController();
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 300,
              height: 100,
              child: ScrollEdgeFade(
                axis: Axis.horizontal,
                child: ListView(
                  controller: controller,
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (var i = 0; i < 5; i++)
                      SizedBox(width: 150, child: Text('Item $i')),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      Offset edges() => tester
          .widget<TweenAnimationBuilder<Offset>>(
            find.byType(TweenAnimationBuilder<Offset>),
          )
          .tween
          .end!;
      expect(edges(), const Offset(0, 1));
      expect(find.byType(BackdropFilter), findsNothing);
      controller.jumpTo(100);
      await tester.pumpAndSettle();
      expect(edges(), const Offset(1, 1));
      expect(controller.offset, 100);
      controller.jumpTo(controller.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(edges(), const Offset(1, 0));
      expect(controller.offset, 450);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  testWidgets(
    'every zoomed programme is fully visible, including first and last',
    (tester) async {
      final nodes = List.generate(5, (_) => FocusNode());
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 500,
              height: 200,
              child: ProgrammeRail(
                cardWidth: 220,
                height: 180,
                itemCount: 5,
                itemBuilder: (_, i) => ProgrammeCard(
                  title: 'Card $i',
                  focusNode: nodes[i],
                  onPressed: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final viewport = tester.getRect(find.byType(ScrollEdgeFade));
      for (var i = 0; i < nodes.length; i++) {
        nodes[i].requestFocus();
        if (i == 1) {
          await tester.pump();
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 100));
          final growing = tester.getRect(
            find.widgetWithText(TextButton, 'Card 1'),
          );
          expect(growing.width, greaterThan(220));
          expect(growing.width, lessThan(220 * 1.05));
        }
        await tester.pumpAndSettle();
        final artwork = tester.getRect(
          find.widgetWithText(TextButton, 'Card $i'),
        );
        expect(artwork.width, closeTo(220 * 1.05, 1));
        if (i == 1) {
          final neighbour = tester.getRect(
            find.widgetWithText(TextButton, 'Card 0'),
          );
          expect(neighbour.width, closeTo(220, 1));
        }
        expect(
          artwork.left,
          greaterThanOrEqualTo(viewport.left),
          reason: 'Left edge of card $i',
        );
        expect(
          artwork.right,
          lessThanOrEqualTo(viewport.right),
          reason: 'Right edge of card $i',
        );
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox());
      for (final node in nodes) {
        node.dispose();
      }
    },
  );
}
