import 'dart:io';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/ronits/tv_icon_pack.dart';

void main() {
  test('pack resolves known packages and preserves unsupported artwork', () {
    expect(
      (tvIconPackArtwork('com.google.android.youtube.tv', 'YouTube TV')
              as AssetImage)
          .assetName,
      'assets/tv-icons/youtube.png',
    );
    expect(tvIconPackArtwork('primevideo', 'Prime Video'), isA<AssetImage>());
    expect(tvIconPackArtwork('sonyliv', 'Sony LIV'), isNull);
    expect(tvIconPackArtwork('unknown.app', 'Unrelated app'), isNull);
    for (final name in tvIconPackNames.values.toSet()) {
      expect(
        File('assets/tv-icons/$name.png').existsSync(),
        true,
        reason: name,
      );
    }
    expect(File('assets/tv-icons/LICENSE').existsSync(), true);
  });

  test('categories distinguish music, video, games and unknown utilities', () {
    expect(
      classifyTvApp('com.google.android.youtube.tv', 'YouTube'),
      'entertainment',
    );
    expect(
      classifyTvApp('com.google.android.apps.youtube.music', 'YouTube Music'),
      'music',
    );
    expect(classifyTvApp('unknown', 'Game', isGame: true), 'games');
    expect(classifyTvApp('unknown', 'Game', platformCategory: 0), 'games');
    expect(classifyTvApp('unknown', 'Audio', platformCategory: 1), 'music');
    expect(classifyTvApp('unknown', 'Files'), 'utilities');
  });
}
