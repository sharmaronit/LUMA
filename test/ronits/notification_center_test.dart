import 'dart:async';
import 'package:luma/ronits/notification_center.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeSource implements NotificationSource {
  FakeSource({this.access = true, List<TvNotification>? items})
    : items = items ?? [];
  bool access;
  bool settingsAvailable = true;
  List<TvNotification> items;
  final opened = <String>[], dismissed = <String>[];
  final _changes = StreamController<void>.broadcast();
  void push(TvNotification item) {
    items = [item, ...items];
    _changes.add(null);
  }

  @override
  Stream<void> get changes => _changes.stream;
  @override
  Future<bool> hasAccess() async => access;
  @override
  Future<List<TvNotification>> load() async => [...items];
  @override
  Future<bool> open(String key) async {
    opened.add(key);
    return true;
  }

  @override
  Future<bool> dismiss(String key) async {
    dismissed.add(key);
    items = items.where((n) => n.key != key).toList();
    return true;
  }

  @override
  Future<int> dismissAll() async {
    final count = items.where((n) => n.clearable).length;
    items = items.where((n) => !n.clearable).toList();
    return count;
  }

  @override
  Future<bool> openAccessSettings() async => settingsAvailable;
}

TvNotification note(String key, String title, {bool clearable = true}) =>
    TvNotification(
      key: key,
      packageName: 'com.example',
      appName: 'Example',
      title: title,
      text: 'Body of $title',
      postTime: DateTime.now().subtract(const Duration(minutes: 5)),
      clearable: clearable,
    );

Future<void> pump(WidgetTester tester, FakeSource source) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 480,
          height: 700,
          child: NotificationCenter(
            source: source,
            packageName: 'app.luma.tvlauncher',
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('asks for access, then shows the adb fallback if needed', (
    tester,
  ) async {
    final source = FakeSource(access: false)..settingsAvailable = false;
    await pump(tester, source);
    expect(find.text('Allow notification access'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('notifications-allow-access')));
    await tester.pumpAndSettle();
    expect(
      find.textContaining(notificationAccessCommand('app.luma.tvlauncher')),
      findsOneWidget,
    );
  });

  testWidgets('lists notifications, dismisses one and clears all', (
    tester,
  ) async {
    final source = FakeSource(
      items: [
        note('a', 'Update ready'),
        note('b', 'Download done'),
        note('c', 'Pinned', clearable: false),
      ],
    );
    await pump(tester, source);
    expect(find.text('Update ready'), findsOneWidget);
    expect(find.textContaining('Example · 5 min ago'), findsNWidgets(3));
    // Non-clearable notifications have no dismiss button.
    expect(find.byTooltip('Dismiss'), findsNWidgets(2));

    await tester.tap(find.byTooltip('Dismiss').first);
    await tester.pumpAndSettle();
    expect(source.dismissed, ['a']);
    expect(find.text('Update ready'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('notifications-clear-all')));
    await tester.pumpAndSettle();
    expect(find.text('Download done'), findsNothing);
    expect(find.text('Pinned'), findsOneWidget);
    expect(find.byKey(const ValueKey('notifications-clear-all')), findsNothing);
  });

  testWidgets('new notifications appear live and empty state reads clearly', (
    tester,
  ) async {
    final source = FakeSource();
    await pump(tester, source);
    expect(find.text('You\'re all caught up'), findsOneWidget);
    source.push(note('n', 'Just arrived'));
    await tester.pumpAndSettle();
    expect(find.text('Just arrived'), findsOneWidget);
    await tester.tap(find.text('Just arrived'));
    await tester.pumpAndSettle();
    expect(source.opened, ['n']);
  });

  test('relative times', () {
    final now = DateTime(2026, 11, 11, 12);
    expect(relativeTime(now, now), 'now');
    expect(relativeTime(now.subtract(const Duration(minutes: 3)), now), '3 min ago');
    expect(relativeTime(now.subtract(const Duration(hours: 2)), now), '2 h ago');
    expect(relativeTime(now.subtract(const Duration(days: 2)), now), '2 d ago');
  });
}
