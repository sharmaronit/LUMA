import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:luma/preview_main.dart';
import 'package:luma/ronits/focus_feedback.dart';
import 'package:luma/ronits/launcher_home.dart';
import 'package:luma/ronits/menu_focus.dart';
import 'package:luma/ronits/glass_surface.dart';
import 'package:luma/ronits/motion.dart';
import 'package:luma/ronits/preview_management.dart';

void tvSize(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(960, 540);
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

void main() {
  testWidgets(
    'dock search keeps selection identity and Undo restores saved order',
    (tester) async {
      tvSize(tester);
      final before = ['youtube', 'netflix', 'jiohotstar'];
      SharedPreferences.setMockInitialValues({'preview_favorites': before});
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(PreviewApp(preferences: prefs));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Add dock apps'));
      await tester.pumpAndSettle();
      final search = find.byType(TextField);
      await tester.enterText(search, 'NET');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('dock-choice-youtube')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('dock-choice-netflix')));
      await tester.pumpAndSettle();
      expect(prefs.getStringList('preview_favorites'), [
        'youtube',
        'jiohotstar',
      ]);
      expect(find.text('Undo'), findsOneWidget);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(prefs.getStringList('preview_favorites'), before);
      expect(find.byType(DockAppPicker), findsOneWidget);
      expect(tester.widget<TextField>(search).controller!.text, 'NET');
      await tester.enterText(search, 'missing app');
      await tester.pumpAndSettle();
      expect(find.text('No apps match your search.'), findsOneWidget);
      expect(find.text('More below'), findsNothing);
      expect(find.text('More above'), findsNothing);
      await tester.tap(find.byTooltip('Clear app search'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(search).controller!.text, isEmpty);
      expect(find.byKey(const ValueKey('dock-choice-youtube')), findsOneWidget);
      await tester.enterText(search, 'YouTube');
      await tester.pumpAndSettle();
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(prefs.getStringList('preview_favorites'), [
        'netflix',
        'jiohotstar',
      ]);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('app management can undo hiding and favourite removal', (
    tester,
  ) async {
    tvSize(tester);
    SharedPreferences.setMockInitialValues({
      'preview_favorites': ['a', 'b'],
    });
    final prefs = await SharedPreferences.getInstance();
    const apps = [
      LauncherAppItem(id: 'a', name: 'App A'),
      LauncherAppItem(id: 'b', name: 'App B'),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () =>
                  showPreviewAppManager(context, prefs, apps, () {}),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('App A'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hide app'));
    await tester.pumpAndSettle();
    expect(prefs.getStringList('preview_hidden'), ['a']);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(prefs.getStringList('preview_hidden'), isEmpty);
    await tester.tap(find.text('Remove favourite'));
    await tester.pumpAndSettle();
    expect(prefs.getStringList('preview_favorites'), ['b']);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(prefs.getStringList('preview_favorites'), ['a', 'b']);
    expect(find.text('Hide app'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('long menus scroll without arrows or edge shadow overlays', (
    tester,
  ) async {
    final scroll = ScrollController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 400,
              height: 180,
              child: GlassSurface(
                mode: LauncherMaterial.solid,
                sheet: true,
                child: ListView(
                  controller: scroll,
                  children: [
                    for (var i = 0; i < 20; i++)
                      SizedBox(height: 50, child: Text('Row $i')),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.keyboard_arrow_up_rounded), findsNothing);
    expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsNothing);
    expect(
      find.descendant(
        of: find.byType(GlassSurface),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is DecoratedBox &&
              widget.decoration is BoxDecoration &&
              ((widget.decoration as BoxDecoration).gradient != null ||
                  ((widget.decoration as BoxDecoration).boxShadow?.isNotEmpty ??
                      false)),
        ),
      ),
      findsNothing,
    );
    scroll.jumpTo(scroll.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.keyboard_arrow_up_rounded), findsNothing);
    expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsNothing);
    expect(
      find.descendant(
        of: find.byType(GlassSurface),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is DecoratedBox &&
              widget.decoration is BoxDecoration &&
              ((widget.decoration as BoxDecoration).gradient != null ||
                  ((widget.decoration as BoxDecoration).boxShadow?.isNotEmpty ??
                      false)),
        ),
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    scroll.dispose();
  });

  testWidgets(
    'Back restores the launching row in scrolled native settings and dialogs',
    (tester) async {
      tvSize(tester);
      final scroll = ScrollController();
      final observer = MenuFocusObserver();
      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [observer],
          home: Builder(
            builder: (context) => Scaffold(
              body: ListView(
                controller: scroll,
                children: [
                  for (var i = 0; i < 20; i++)
                    TvMenuRow(
                      key: ValueKey('parent-$i'),
                      title: 'Option $i',
                      autofocus: i == 0,
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (context) => Scaffold(
                            body: TextButton(
                              autofocus: true,
                              onPressed: () => showLumaDialog<void>(
                                context: context,
                                builder: (context) => Dialog(
                                  child: TextButton(
                                    autofocus: true,
                                    onPressed: () => Navigator.pop(context),
                                    child: const Text('Close child'),
                                  ),
                                ),
                              ),
                              child: const Text('Open child'),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Option 12'), 150);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Option 12'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('Close child'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Close child'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('Close child'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      final row = find.byKey(const ValueKey('parent-12'));
      expect(
        find.descendant(
          of: row,
          matching: find.byWidgetPredicate(
            (w) => w is Focus && w.focusNode?.hasPrimaryFocus == true,
          ),
        ),
        findsOneWidget,
      );
      expect(scroll.offset, greaterThan(0));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      scroll.dispose();
    },
  );
}
