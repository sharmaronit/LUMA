import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/ronits/glass_surface.dart';
import 'package:luma/ronits/launcher_home.dart';
import 'package:luma/ronits/voice_search.dart';
import 'package:luma/ronits/voice_session.dart';
import 'package:luma/ronits/motion.dart';
import 'package:luma/ronits/search_panel.dart';

class TestVoiceSession implements VoiceSession {
  final controller = StreamController<VoiceEvent>.broadcast();
  int starts = 0, stops = 0;
  bool disposed = false;
  @override
  Stream<VoiceEvent> get events => controller.stream;
  @override
  Future<void> start() async {
    starts++;
  }

  @override
  Future<void> stop() async {
    stops++;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    await controller.close();
  }
}

void main() {
  testWidgets(
    'voice island drops from the top, expands for speech and exits upward',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(960, 540);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final session = TestVoiceSession();
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showLumaDialog<void>(
                  context: context,
                  fromTop: true,
                  builder: (_) => VoiceSearchDialog(
                    session: session,
                    mode: LauncherMaterial.minimal,
                    onSearch: (_) {},
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));
      final island = find.byKey(const ValueKey('voice-island'));
      final enteringTop = tester.getTopLeft(island).dy;
      await tester.pumpAndSettle();
      final settled = tester.getRect(island);
      expect(enteringTop, lessThan(settled.top));
      expect(settled.top, 16);
      expect(settled.height, lessThan(90));
      expect(settled.width, 340);
      expect(find.byType(FloatingSearchPanel), findsNothing);
      expect(find.byType(BackdropFilter), findsNothing);
      session.controller.add(const VoiceEvent('processing', text: 'YouTube'));
      await tester.pumpAndSettle();
      expect(tester.getSize(island).width, 520);
      expect(tester.getTopLeft(island).dy, 16);
      expect(tester.getRect(island).bottom, lessThan(540));
      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));
      expect(tester.getTopLeft(island).dy, lessThan(settled.top));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('voice-island')), findsNothing);
      expect(session.disposed, true);
      expect(tester.takeException(), isNull);
    },
  );
  test('voice app commands are cleaned without changing app names', () {
    expect(voiceAppQuery('Please open YouTube!'), 'YouTube');
    expect(voiceAppQuery('search for Netflix.'), 'Netflix');
    expect(voiceAppQuery('JioHotstar'), 'JioHotstar');
  });
  testWidgets(
    'final speech automatically searches installed apps and disposes the session',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1280, 720);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final session = TestVoiceSession();
      final app = LauncherAppItem(
        id: 'youtube',
        name: 'YouTube',
        artwork: Future.value(null),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: LauncherHome(
            apps: [
              app,
              LauncherAppItem(id: 'netflix', name: 'Netflix'),
            ],
            favorites: [app],
            wallpaper: const AssetImage('assets/mountain.jpg'),
            mode: LauncherMaterial.solid,
            createVoiceSession: () => session,
            reducedMotion: true,
            onMaterialChanged: (_) {},
            onLaunch: (_) async {},
            onSettings: () {},
            onWifi: () {},
            onManage: () {},
            onFavorite: (_) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Voice search'));
      await tester.pumpAndSettle();
      expect(session.starts, 1);
      session.controller.add(const VoiceEvent('listening'));
      await tester.pumpAndSettle();
      expect(find.text('Listening…'), findsOneWidget);
      session.controller.add(const VoiceEvent('partial', text: 'Open You'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('voice-transcript')))
            .data,
        'Open You',
      );
      session.controller.add(const VoiceEvent('result', text: 'Open YouTube'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(session.disposed, isTrue);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'YouTube',
      );
      expect(
        find.byKey(const ValueKey('search-result-youtube')),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('voice error offers an icon retry and cancellation', (
    tester,
  ) async {
    final session = TestVoiceSession();
    String? query;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => VoiceSearchDialog(
                session: session,
                mode: LauncherMaterial.solid,
                reducedMotion: true,
                onSearch: (value) => query = value,
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    session.controller.add(
      const VoiceEvent('error', message: 'Microphone access denied'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Microphone access needed'), findsOneWidget);
    expect(find.text('Type instead'), findsNothing);
    expect(session.stops, 1);
    await tester.tap(find.byTooltip('Try again'));
    await tester.pumpAndSettle();
    expect(session.starts, 2);
    session.controller.add(
      const VoiceEvent('error', message: 'Speech unavailable'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Close voice search'));
    await tester.pumpAndSettle();
    expect(query, isNull);
    expect(session.disposed, isTrue);
  });
  testWidgets('voice session is disposed when closed before speech completes', (
    tester,
  ) async {
    final session = TestVoiceSession();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => VoiceSearchDialog(
                session: session,
                mode: LauncherMaterial.solid,
                reducedMotion: true,
                onSearch: (_) {},
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Close voice search'));
    await tester.pumpAndSettle();
    expect(session.disposed, isTrue);
    await tester.pumpWidget(const SizedBox());
  });
}
