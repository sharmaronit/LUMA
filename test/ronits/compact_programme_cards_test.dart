import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/ronits/cinematic_backdrop.dart';
import 'package:luma/ronits/programme_rail.dart';

void main() {
  testWidgets(
    'compact rail keeps metadata below artwork and navigates with large text',
    (tester) async {
      tester.view.physicalSize = const Size(960, 540);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final nodes = List.generate(4, (_) => FocusNode());
      var artworkChanges = 0;
      for (final scale in [1.0, 1.5]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MediaQuery(
                data: MediaQueryData(
                  size: const Size(960, 540),
                  textScaler: TextScaler.linear(scale),
                ),
                child: NotificationListener<ProgrammeArtworkFocus>(
                  onNotification: (event) {
                if (event.image != null) artworkChanges++;
                    return true;
                  },
                  child: ProgrammeRail(
                    compact: true,
                    cardWidth: 246,
                    height: 220,
                    itemCount: 4,
                    itemBuilder: (_, i) => ProgrammeCard(
                      title: 'Programme $i',
                      provider: 'Streaming service',
                      compact: true,
                      focusNode: nodes[i],
                      artwork: const AssetImage('assets/tv-icons/netflix.png'),
                      onPressed: () {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final art = find.byKey(const ValueKey('compact-programme-artwork'));
        expect(
          tester.getRect(find.text('Programme 0')).top,
          greaterThan(tester.getRect(art.first).bottom),
        );
        expect(
          tester.getRect(find.text('Streaming service').first).top,
          greaterThanOrEqualTo(tester.getRect(find.text('Programme 0')).bottom),
        );
        expect(tester.getRect(find.text('Programme 2')).right, lessThan(960));
        expect(
          find.byKey(const ValueKey('programme-artwork-gradient')),
          findsNothing,
        );
        nodes.first.requestFocus();
        await tester.pumpAndSettle();
        for (var i = 1; i < 4; i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
          await tester.pumpAndSettle();
          expect(nodes[i].hasFocus, isTrue);
        }
        expect(
          artworkChanges,
          0,
          reason: 'Home retains its wallpaper while browsing cards',
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      }
      for (final node in nodes) {
        node.dispose();
      }
    },
  );
}
