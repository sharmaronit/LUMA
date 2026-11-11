import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/ronits/profiles.dart';
import 'package:luma/ronits/reference_control_center.dart';

Future<void> pump(
  WidgetTester tester,
  List<Profile> profiles,
  ValueChanged<Profile> onSelected,
) async {
  tester.view.physicalSize = const Size(1280, 720);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topRight,
          child: SizedBox(
            width: 300,
            child: SingleChildScrollView(
              child: ReferenceControlCenter(
                onWifi: () {},
                onDeviceSettings: (_) {},
                onSettings: () {},
                onApps: () {},
                onSearch: () {},
                profiles: profiles,
                activeProfile: profiles.first,
                onProfileSelected: onSelected,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  const people = [
    Profile('p1', 'Person 1'),
    Profile('p2', 'Asha'),
    Profile('p3', 'Dev'),
  ];
  const tile = ValueKey("quick-control-Profile");

  testWidgets('one person: no tile', (tester) async {
    await pump(tester, const [Profile('p1', 'Person 1')], (_) {});
    expect(find.byKey(tile), findsNothing);
  });

  testWidgets('the tile opens a drop-down list and the remote picks a person', (
    tester,
  ) async {
    Profile? chosen;
    await pump(tester, people, (profile) => chosen = profile);
    expect(find.text('Person 1'), findsOneWidget);
    await tester.tap(find.byKey(tile));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('who-watching-p2')), findsOneWidget);
    expect(find.byKey(const ValueKey('who-watching-p3')), findsOneWidget);
    // Focus starts on the person watching now: one Down reaches the next
    // person, as it must on a real remote.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(chosen?.id, 'p2');
    expect(find.byKey(const ValueKey('who-watching-p2')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('OK straight away keeps the current person; Back closes', (
    tester,
  ) async {
    var calls = 0;
    await pump(tester, people, (_) => calls++);
    await tester.tap(find.byKey(tile));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(find.byKey(const ValueKey('who-watching-list')), findsNothing);
    await tester.tap(find.byKey(tile));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('who-watching-list')), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('who-watching-list')), findsNothing);
    expect(calls, 0);
  });

  testWidgets('choosing the person already watching does nothing', (
    tester,
  ) async {
    var calls = 0;
    await pump(tester, people, (_) => calls++);
    await tester.tap(find.byKey(tile));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('who-watching-p1')));
    await tester.pumpAndSettle();
    expect(calls, 0);
  });
}
