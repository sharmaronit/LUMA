import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:luma/preview_main.dart';
import 'package:luma/ronits/preview_setup.dart';

void main() {
  test(
    'restored preview activates once and preserves app choices and later themes',
    () async {
      SharedPreferences.setMockInitialValues({
        'minimal_background': 'charcoal',
        'home_card_size': 'large',
        'home_selected_library': true,
        'home_library_offset': 900.0,
        'preview_favorites': ['netflix', 'youtube'],
        'preview_hidden': ['vlc'],
        'preview_recent': ['netflix'],
      });
      final preferences = await SharedPreferences.getInstance();
      await prepareRestoredPreview(preferences);
      expect(preferences.getString('minimal_background'), 'glass');
      expect(preferences.getString('home_card_size'), 'medium');
      expect(preferences.getBool('home_selected_library'), false);
      expect(preferences.getDouble('home_library_offset'), 0);
      expect(preferences.getStringList('preview_favorites'), [
        'netflix',
        'youtube',
      ]);
      expect(preferences.getStringList('preview_hidden'), ['vlc']);
      expect(preferences.getStringList('preview_recent'), ['netflix']);
      await preferences.setString('minimal_background', 'chocolate');
      await preferences.setString('home_card_size', 'small');
      await prepareRestoredPreview(preferences);
      expect(preferences.getString('minimal_background'), 'chocolate');
      expect(preferences.getString('home_card_size'), 'small');
    },
  );

  testWidgets(
    'browser startup migrates an older appearance to the restored Home',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      SharedPreferences.setMockInitialValues({
        'minimal_background': 'wallpaper',
        'home_card_size': 'large',
        'home_selected_library': true,
        'home_library_offset': 700.0,
        'home_wallpaper_accent': false,
      });
      final preferences = await SharedPreferences.getInstance();
      await prepareRestoredPreview(preferences);
      await tester.pumpWidget(PreviewApp(preferences: preferences));
      await tester.pumpAndSettle();
      final dock = tester.getRect(
        find.byKey(const ValueKey('home-favourites-dock')),
      );
      expect(dock.top, greaterThan(900 * .58));
      expect(find.text('Favourite apps'), findsNothing);
      expect(find.text('From your apps').hitTestable(), findsNothing);
      expect(find.byKey(const ValueKey('home-wallpaper')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
