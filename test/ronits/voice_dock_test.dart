import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/ronits/glass_surface.dart';
import 'package:luma/ronits/luma_glass_theme.dart';
import 'package:luma/ronits/voice_search.dart';
import 'package:luma/ronits/voice_session.dart';

class _Session implements VoiceSession {
  final controller = StreamController<VoiceEvent>.broadcast();
  bool disposed = false;
  int stops = 0;
  @override
  Stream<VoiceEvent> get events => controller.stream;
  @override
  Future<void> start() async {}
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

Future<void> openDock(
  WidgetTester tester,
  _Session session,
  String theme,
  ValueChanged<String> search,
) async {
  await tester.pumpWidget(
    MenuAppearanceScope(
      mode: LauncherMaterial.minimal,
      minimalBackground: theme,
      blurBuilder: (child, sigma, saturation) =>
          KeyedSubtree(key: const ValueKey('cached-voice-glass'), child: child),
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => VoiceSearchDialog(
                  session: session,
                  mode: LauncherMaterial.minimal,
                  reducedMotion: true,
                  onSearch: search,
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'backgrounding cancels pending voice search and stops the microphone',
    (tester) async {
      final session = _Session();
      final queries = <String>[];
      await openDock(tester, session, 'charcoal', queries.add);
      session.controller.add(const VoiceEvent('result', text: 'Open Netflix'));
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(seconds: 1));
      expect(queries, isEmpty);
      expect(session.stops, greaterThan(0));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('Voice unavailable'), findsOneWidget);
      await tester.tap(find.byTooltip('Close voice search'));
      await tester.pumpAndSettle();
    },
  );
  for (final theme in ['charcoal', 'glass', 'glass-real']) {
    testWidgets('voice dock uses the $theme surface and minimal controls', (
      tester,
    ) async {
      final session = _Session();
      await openDock(tester, session, theme, (_) {});
      expect(
        tester.widget<LumaGlassPanel>(find.byType(LumaGlassPanel)).enabled,
        theme != 'charcoal',
      );
      expect(
        find.byKey(const ValueKey('cached-voice-glass')),
        theme != 'charcoal' ? findsOneWidget : findsNothing,
      );
      expect(
        find.byType(BackdropFilter),
        findsNothing,
      );
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Voice search'), findsNothing);
      expect(find.text('Show results'), findsNothing);
      expect(find.byType(IconButton), findsNWidgets(2));
      expect(
        tester.getSize(find.byKey(const ValueKey('voice-island'))).height,
        lessThan(90),
      );
      await tester.tap(find.byTooltip('Close voice search'));
      await tester.pumpAndSettle();
      expect(session.disposed, true);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('final speech searches once without confirmation', (
    tester,
  ) async {
    final session = _Session();
    final queries = <String>[];
    await openDock(tester, session, 'charcoal', queries.add);
    session.controller.add(const VoiceEvent('result', text: 'Open Netflix'));
    session.controller.add(const VoiceEvent('result', text: 'Open YouTube'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(queries, ['Netflix']);
    expect(session.disposed, true);
  });
  testWidgets('close cancels an automatic search that has not fired', (
    tester,
  ) async {
    final session = _Session();
    final queries = <String>[];
    await openDock(tester, session, 'glass', queries.add);
    session.controller.add(const VoiceEvent('result', text: 'Netflix'));
    await tester.pump();
    await tester.tap(find.byTooltip('Close voice search'));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(queries, isEmpty);
    expect(session.disposed, true);
  });
  testWidgets('empty speech stays in the dock for retry', (tester) async {
    final session = _Session();
    final queries = <String>[];
    await openDock(tester, session, 'charcoal', queries.add);
    session.controller.add(const VoiceEvent('result'));
    await tester.pumpAndSettle();
    expect(find.text('Nothing heard'), findsOneWidget);
    expect(find.byTooltip('Try again'), findsOneWidget);
    expect(queries, isEmpty);
    await tester.tap(find.byTooltip('Close voice search'));
    await tester.pumpAndSettle();
  });
}
