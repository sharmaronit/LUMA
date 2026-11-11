import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:luma/database.dart';
import 'package:luma/providers/apps_service.dart';
import 'package:luma/luma_channel.dart';
import '../mocks.mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'successful native launches persist history; failed launches do not',
    () async {
      SharedPreferences.setMockInitialValues({});
      final database = LumaDatabase.inMemory();
      final channel = MockLumaChannel();
      when(
        channel.getApplicationBanner(any),
      ).thenAnswer((_) async => Uint8List(0));
      when(
        channel.getApplicationIcon(any),
      ).thenAnswer((_) async => Uint8List(0));
      when(channel.getApplications()).thenAnswer(
        (_) async => [
          for (final id in ['a', 'b'])
            {
              'packageName': id,
              'name': id,
              'version': '1',
              'sideloaded': false,
            },
        ],
      );
      when(channel.launchApp('a')).thenAnswer((_) async {});
      when(channel.launchApp('b')).thenThrow(StateError('App unavailable'));
      final service = AppsService(channel, database);
      for (var i = 0; i < 100 && !service.initialized; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      final a = service.applications.firstWhere(
        (app) => app.packageName == 'a',
      );
      final b = service.applications.firstWhere(
        (app) => app.packageName == 'b',
      );
      await service.launchApp(a);
      expect(a.lastLaunchedAt, isNotNull);
      await expectLater(service.launchApp(b), throwsStateError);
      expect(b.lastLaunchedAt, isNull);
      final rows = await database.getApplications();
      expect(
        rows.firstWhere((row) => row.packageName == 'a').lastLaunchedAt,
        isNotNull,
      );
      expect(
        rows.firstWhere((row) => row.packageName == 'b').lastLaunchedAt,
        isNull,
      );
      service.dispose();
      final reopened = AppsService(channel, database);
      for (var i = 0; i < 100 && !reopened.initialized; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(reopened.initialized, isTrue);
      expect(
        reopened.applications
            .firstWhere((app) => app.packageName == 'a')
            .lastLaunchedAt,
        isNotNull,
      );
      expect(
        reopened.applications
            .firstWhere((app) => app.packageName == 'b')
            .lastLaunchedAt,
        isNull,
      );
      reopened.dispose();
      await database.close();
    },
  );
  test('Android false launch results surface as errors', () async {
    const channel = MethodChannel('app.luma.tvlauncher/method');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (_) async => false);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    await expectLater(
      LumaChannel().launchApp('unavailable'),
      throwsA(isA<PlatformException>()),
    );
    await expectLater(
      LumaChannel().launchActivityFromAction('unavailable'),
      throwsA(isA<PlatformException>()),
    );
  });
}
