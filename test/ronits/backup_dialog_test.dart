import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/ronits/backup_dialog.dart';
import 'package:luma/ronits/launcher_backup.dart';

void main() {
  testWidgets(
    'remote Paste handles an empty clipboard and still requires review',
    (tester) async {
      tester.view.physicalSize = const Size(960, 540);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      String? clipboard;
      var restored = 0;
      final data = LauncherBackup({}, {
        'categories': [],
        'hidden': [],
      }).encode();
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.getData')
            return clipboard == null ? null : {'text': clipboard};
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showBackupDialog(
                  context,
                  export: () async => data,
                  restore: (_) async {
                    restored++;
                  },
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Enter backup JSON'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Paste backup'));
      await tester.pumpAndSettle();
      expect(
        find.text('The clipboard is empty. Copy a backup first.'),
        findsOneWidget,
      );
      clipboard = data;
      await tester.tap(find.text('Paste backup'));
      await tester.pumpAndSettle();
      expect(find.text('Apply restore'), findsNothing);
      await tester.scrollUntilVisible(
        find.text('Review JSON'),
        100,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Review JSON'));
      await tester.pumpAndSettle();
      expect(restored, 0);
      tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .jumpTo(0);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply restore'));
      await tester.pumpAndSettle();
      expect(restored, 1);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'local restore is reviewed before applying and fits TV viewport',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(960, 540);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final data = LauncherBackup(
        {'launcher_material': 'solid'},
        {'categories': [], 'hidden': []},
      ).encode();
      var restored = 0;
      var saved = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showBackupDialog(
                  context,
                  export: () async => data,
                  restore: (_) async {
                    restored++;
                  },
                  saveLocal: (value) async {
                    saved++;
                    return 'Local backup saved.';
                  },
                  readLocal: () async => data,
                  readFile: () async => null,
                  writeFile: (_) async => false,
                ),
                child: const Text('Open backup'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open backup'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Save local backup'));
      await tester.pumpAndSettle();
      expect(saved, 1);
      await tester.tap(find.text('Load local backup'));
      await tester.pumpAndSettle();
      expect(restored, 0);
      expect(find.text('Apply restore'), findsOneWidget);
      await tester.tap(find.text('Apply restore'));
      await tester.pumpAndSettle();
      expect(restored, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('invalid JSON shows an error and cannot apply', (tester) async {
    var restored = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showBackupDialog(
                context,
                export: () async => '{}',
                restore: (_) async {
                  restored++;
                },
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enter backup JSON'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '{bad');
    await tester.drag(find.byType(ListView), const Offset(0, -220));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Review JSON'));
    await tester.tap(find.text('Review JSON'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Backup operation failed:'), findsOneWidget);
    expect(find.text('Apply restore'), findsNothing);
    expect(restored, 0);
    await tester.pumpWidget(const SizedBox());
  });
}
