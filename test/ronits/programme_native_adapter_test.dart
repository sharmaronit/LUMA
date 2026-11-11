import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:luma/luma_channel.dart';
import 'package:luma/providers/watch_next_service.dart';
import 'package:luma/ronits/programme_library.dart';
import 'package:luma/models/watch_next_item.dart';

ProgrammeEntry entry(int id, String title, String provider) => ProgrammeEntry(
  WatchNextItem(
    id: id,
    title: title,
    packageName: provider,
    contentId: 'episode-$id',
    intentUri: 'intent://episode-$id',
  ),
  provider,
);
void main() {
  testWidgets(
    'native watchlist playback preserves deep links and Open app clears programme links',
    (tester) async {
      const channel = MethodChannel('app.luma.tvlauncher/method');
      final calls = <Map>[];
      final poster = Completer<Uint8List>();
      var posterLoads = 0;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (call.method == 'checkWatchNextPermission') return true;
        if (call.method == 'getWatchNextItems')
          return [
            {
              ...entry(9, 'Native show', 'native.tv').item.toMap(),
              'posterUri': 'content://poster/9',
            },
          ];
        if (call.method == 'loadContentUriImage') {
          posterLoads++;
          return poster.future;
        }
        if (call.method == 'launchWatchNextItem') {
          calls.add(call.arguments as Map);
          return true;
        }
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      SharedPreferences.setMockInitialValues({});
      await SharedPreferences.getInstance();
      await ProgrammeLibrary.shared.ready();
      final service = WatchNextService(LumaChannel());
      await tester.pump();
      await service.refreshPermissionAndItems();
      final library = ProgrammeLibrary.shared;
      final programme = library.source.single;
      final firstArtwork = library.loadArtwork!(programme);
      final secondArtwork = library.loadArtwork!(programme);
      poster.complete(Uint8List.fromList([1, 2, 3]));
      expect(await firstArtwork, isNotNull);
      expect(await secondArtwork, isNotNull);
      expect(posterLoads, 1);
      expect(await library.launch!(programme, false), true);
      expect(calls.single['action'], 'intent://episode-9');
      expect(calls.single['contentId'], 'episode-9');
      expect(await library.launch!(programme, true), true);
      expect(calls.last['packageName'], 'native.tv');
      expect(calls.last['action'], isNull);
      expect(calls.last['contentId'], isNull);
      service.dispose();
    },
  );
}
