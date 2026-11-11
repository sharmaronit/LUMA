import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/ronits/profiles.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeHost implements ProfileHost {
  List<String> bar = ['netflix', 'youtube'];
  String wallpaper = 'ocean';
  final saved = <String, String>{};
  int reloads = 0;
  @override
  Future<List<String>> favourites() async => [...bar];
  @override
  Future<void> setFavourites(List<String> packages) async =>
      bar = [...packages];
  @override
  Future<void> saveWallpaper(String profileId) async =>
      saved[profileId] = wallpaper;
  @override
  Future<void> restoreWallpaper(String profileId) async =>
      wallpaper = saved[profileId] ?? wallpaper;
  @override
  Future<void> deleteWallpaper(String profileId) async =>
      saved.remove(profileId);
  @override
  void settingsChanged() => reloads++;
}

Future<(ProfileService, SharedPreferences, FakeHost)> make([
  Map<String, Object> initial = const {},
]) async {
  SharedPreferences.setMockInitialValues(initial);
  final prefs = await SharedPreferences.getInstance();
  final host = FakeHost();
  return (ProfileService(prefs, host: host), prefs, host);
}

void main() {
  test('starts with one person and no switcher needed', () async {
    final (service, _, _) = await make();
    expect(service.profiles.map((p) => p.name), ['Person 1']);
    expect(service.active.id, 'p1');
  });

  test('a new person starts as a copy, then keeps their own look', () async {
    final (service, prefs, host) = await make({
      'minimal_background': 'glass',
      'home_clock_size': '40',
      'wallpaper_selected_asset': 'assets/wallpapers/coast.jpg',
      'lite_mode': 'off',
    });
    final second = (await service.add())!;
    expect(second.name, 'Person 2');

    await service.switchTo(second.id);
    expect(service.active.id, second.id);
    // Copy of person 1 until changed.
    expect(prefs.getString('minimal_background'), 'glass');
    expect(host.bar, ['netflix', 'youtube']);

    // Person 2 personalises.
    await prefs.setString('minimal_background', 'charcoal');
    await prefs.setBool('depth_clock', false);
    await prefs.remove('home_clock_size');
    await prefs.setString('lite_mode', 'on'); // shared, not personal
    host
      ..bar = ['prime']
      ..wallpaper = 'dolomites';

    await service.switchTo('p1');
    expect(prefs.getString('minimal_background'), 'glass');
    expect(prefs.getString('home_clock_size'), '40');
    expect(prefs.getBool('depth_clock'), isNull);
    expect(prefs.getString('lite_mode'), 'on');
    expect(host.bar, ['netflix', 'youtube']);
    expect(host.wallpaper, 'ocean');

    await service.switchTo(second.id);
    expect(prefs.getString('minimal_background'), 'charcoal');
    expect(prefs.getString('home_clock_size'), isNull);
    expect(prefs.getBool('depth_clock'), isFalse);
    expect(host.bar, ['prime']);
    expect(host.wallpaper, 'dolomites');
    expect(host.reloads, 3);
    expect(service.generation, 3);
  });

  test('the list and the active person survive a restart', () async {
    final (service, prefs, _) = await make();
    final second = (await service.add('  Asha  '))!;
    expect(second.name, 'Asha');
    await service.switchTo(second.id);
    final restarted = ProfileService(prefs);
    expect(restarted.profiles.map((p) => p.name), ['Person 1', 'Asha']);
    expect(restarted.active.name, 'Asha');
  });

  test('rename, remove and limits', () async {
    final (service, prefs, host) = await make();
    await service.rename('p1', 'A name that is far too long for a badge');
    expect(service.active.name.length, 20);
    await service.rename('p1', '   ');
    expect(service.active.name.length, 20);

    final second = (await service.add())!;
    await service.switchTo(second.id);
    await service.switchTo('p1');
    expect(prefs.getString('luma_profile_data_${second.id}'), isNotNull);

    expect(await service.remove('p1'), isFalse, reason: 'active profile');
    expect(await service.remove(second.id), isTrue);
    expect(prefs.getString('luma_profile_data_${second.id}'), isNull);
    expect(host.saved.containsKey(second.id), isFalse);
    expect(await service.remove('p1'), isFalse, reason: 'last profile');

    while (service.canAdd) {
      await service.add();
    }
    expect(service.profiles.length, ProfileService.maxProfiles);
    expect(await service.add(), isNull);
    expect(service.profiles.map((p) => p.id).toSet().length, 6);
  });

  test('a damaged stored list falls back to one person', () async {
    final (service, _, _) = await make({'luma_profiles': '{not json'});
    expect(service.profiles.length, 1);
  });

  testWidgets('settings dialog adds a person and switches to them', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final (service, _, _) = await make();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showProfilesSettings(context, service),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('profile-remove-p2')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('profile-add')));
    await tester.pumpAndSettle();
    expect(find.text('Person 2'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('profile-p2')));
    await tester.tap(find.byKey(const ValueKey('profile-p2')));
    await tester.pumpAndSettle();
    expect(service.active.name, 'Person 2');
    expect(find.text('Profiles'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
