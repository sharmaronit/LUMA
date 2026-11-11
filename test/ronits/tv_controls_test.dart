import 'package:luma/ronits/reference_control_center.dart';
import 'package:luma/ronits/tv_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeTv implements TvControls {
  FakeTv({this.inputList = const [], this.allowed = false});
  List<TvInput> inputList;
  bool allowed;
  DateTime? end;
  final switched = <String>[];
  int permissionRequests = 0;
  @override
  Future<List<TvInput>> inputs() async => inputList;
  @override
  Future<bool> switchInput(String id) async {
    switched.add(id);
    return true;
  }

  @override
  Future<DateTime?> sleepEnd() async => end;
  @override
  Future<DateTime?> setSleep(int minutes) async =>
      end = minutes == 0 ? null : DateTime.now().add(Duration(minutes: minutes));
  @override
  Future<bool> canTurnOff() async => allowed;
  @override
  Future<bool> requestTurnOff() async {
    permissionRequests++;
    allowed = true;
    return true;
  }
}

Future<void> pump(WidgetTester tester, FakeTv tv) async {
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
                tvControls: tv,
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
  test('sleep labels', () {
    final now = DateTime(2026, 11, 11, 22);
    expect(sleepLabel(null, now), 'Off');
    expect(sleepLabel(now.add(const Duration(minutes: 29, seconds: 10)), now), '30 min left');
    expect(sleepLabel(now.add(const Duration(minutes: 90)), now), '1 h 30 min left');
    expect(sleepLabel(now.subtract(const Duration(minutes: 1)), now), 'Off');
    expect(sleepChoiceLabel(90), '1 hour 30 min');
    expect(sleepChoiceLabel(60), '1 hour');
    expect(sleepChoiceLabel(120), '2 hours');
    expect(sleepChoiceLabel(15), '15 minutes');
  });

  testWidgets('streaming boxes show the sleep timer but no input switcher', (
    tester,
  ) async {
    await pump(tester, FakeTv());
    expect(find.byKey(const ValueKey('quick-control-Sleep timer')), findsOneWidget);
    expect(find.byKey(const ValueKey('quick-control-Input')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sleep timer asks for the turn-off permission, then sets and clears', (
    tester,
  ) async {
    final tv = FakeTv();
    await pump(tester, tv);
    await tester.tap(find.byKey(const ValueKey('quick-control-Sleep timer')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sleep-allow-turn-off')));
    await tester.pumpAndSettle();
    expect(tv.permissionRequests, 1);
    expect(find.byKey(const ValueKey('sleep-allow-turn-off')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('sleep-30')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('quick-control-Sleep timer-caption')))
          .data,
      anyOf('30 min left', '29 min left'),
    );
    await tester.tap(find.byKey(const ValueKey('quick-control-Sleep timer')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sleep-0')));
    await tester.pumpAndSettle();
    expect(tv.end, isNull);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('quick-control-Sleep timer-caption')))
          .data,
      'Off',
    );
  });

  testWidgets('TVs with HDMI inputs can switch input', (tester) async {
    final tv = FakeTv(
      inputList: const [
        TvInput(id: 'hdmi1', label: 'HDMI 1'),
        TvInput(id: 'hdmi2', label: 'PlayStation'),
      ],
    );
    await pump(tester, tv);
    expect(find.text('2 sources'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('quick-control-Input')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('PlayStation'));
    await tester.pumpAndSettle();
    expect(tv.switched, ['hdmi2']);
  });
}
