import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/ronits/quick_settings.dart';
import 'package:luma/ronits/glass_surface.dart';

void main() {
  testWidgets(
    'network status refreshes without rebuilding the launcher and timer disposes',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      var network = 'Ethernet · Internet available';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              child: QuickSettingsContent(
                initialCategory: 'Device',
                mode: LauncherMaterial.solid,
                reducedMotion: true,
                onMaterialChanged: (_) {},
                onWifi: () {},
                onSettings: () {},
                onDeviceSettings: (_) {},
                loadConnectionStatus: () async => {
                  'network': network,
                  'bluetooth': 'Bluetooth off',
                  'defaultHome': true,
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Ethernet · Internet available'), findsOneWidget);
      expect(find.text('Bluetooth off'), findsOneWidget);
      network = 'Disconnected · No validated Internet';
      await tester.pump(const Duration(seconds: 10));
      await tester.pump();
      expect(find.text(network), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'optional Bluetooth status permission is requested only on selection',
    (tester) async {
      var allowed = false;
      var requests = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              child: QuickSettingsContent(
                initialCategory: 'Device',
                fullSettings: true,
                mode: LauncherMaterial.solid,
                reducedMotion: true,
                onMaterialChanged: (_) {},
                onWifi: () {},
                onSettings: () {},
                onDeviceSettings: (_) {},
                loadConnectionStatus: () async => {
                  'bluetoothPermission': allowed,
                },
                onBluetoothStatusPermission: () async {
                  requests++;
                  allowed = true;
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(requests, 0);
      await tester.tap(find.text('Allow accessory status'));
      await tester.pumpAndSettle();
      expect(requests, 1);
      expect(find.text('Allow accessory status'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
