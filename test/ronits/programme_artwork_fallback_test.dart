import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:luma/luma_channel.dart';
import 'package:luma/providers/watch_next_service.dart';
import 'package:luma/ronits/programme_library.dart';
import 'package:luma/models/watch_next_item.dart';

void main() {
  testWidgets(
    'programme artwork falls back when the shared backdrop is unavailable',
    (tester) async {
      const channel = MethodChannel('app.luma.tvlauncher/method');
      final loaded = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (call.method == 'checkWatchNextPermission') return true;
        if (call.method == 'getWatchNextItems') return <Map>[];
        if (call.method == 'loadContentUriImage') {
          final uri = call.arguments as String;
          loaded.add(uri);
          return Uint8List.fromList(uri.endsWith('poster') ? [1, 2, 3] : []);
        }
        return null;
      });
      SharedPreferences.setMockInitialValues({});
      await ProgrammeLibrary.shared.ready();
      final service = WatchNextService(LumaChannel());
      await tester.pump();
      final result = await ProgrammeLibrary.shared.loadArtwork!(
        ProgrammeEntry(
          WatchNextItem(
            id: 45,
            title: 'Fallback',
            backdropUri: 'content://test/backdrop',
            posterUri: 'content://test/poster',
          ),
          'Test',
        ),
      );
      expect(result, isNotNull);
      expect(loaded, ['content://test/backdrop', 'content://test/poster']);
      service.dispose();
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      );
    },
  );
}
