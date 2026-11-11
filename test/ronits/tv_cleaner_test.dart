import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/ronits/tv_cleaner.dart';

class FakeShell implements CleanerShell {
  FakeShell({
    Set<String>? enabled,
    Set<String>? disabled,
    this.status = ShellStatus.ok,
    this.home = false,
    this.locked = const {},
  }) : enabled = enabled ?? {},
       disabled = disabled ?? {};
  final Set<String> enabled, disabled;
  ShellStatus status;
  bool home;

  /// Packages the TV refuses to change.
  final Set<String> locked;
  final commands = <String>[];
  int developerOpens = 0;

  @override
  Future<bool> lumaIsHome() async => home;
  @override
  Future<void> openDeveloperOptions() async => developerOpens++;
  @override
  Future<ShellResult> run(
    List<String> list, {
    bool waitForApproval = false,
  }) async {
    if (status != ShellStatus.ok) return ShellResult(status);
    commands.addAll(list);
    return ShellResult(ShellStatus.ok, [
      for (final command in list)
        if (command == 'pm list packages -e')
          enabled.map((p) => 'package:$p').join('\n')
        else if (command == 'pm list packages -d')
          disabled.map((p) => 'package:$p').join('\n')
        else if (command.startsWith('pm disable-user --user 0 '))
          _set(command.split(' ').last, false)
        else if (command.startsWith('pm enable '))
          _set(command.split(' ').last, true)
        else
          '',
    ]);
  }

  String _set(String package, bool on) {
    if (locked.contains(package)) return 'Error: java.lang.SecurityException';
    (on ? disabled : enabled).remove(package);
    (on ? enabled : disabled).add(package);
    return 'Package $package new state: ${on ? 'enabled' : 'disabled-user'}';
  }
}

class MemoryStore implements CleanerStore {
  Set<String> value = {};
  @override
  Future<Set<String>> load() async => {...value};
  @override
  Future<void> save(Set<String> packages) async => value = {...packages};
}

const lists = {
  'common': '''
# comment
never|com.android.systemui|System UI
never|com.google.android.gms|Play services
safe|com.example.ads|Ad service
safe|com.google.android.gms|Wrongly listed
aggressive|com.example.store|OEM store
''',
  'xiaomi-patchwall': '''
safe|com.xiaomi.analytics|Xiaomi analytics
launcher|com.mitv.tvhome|PatchWall
''',
  'fire-tv': 'safe|com.amazon.ads|Amazon ads\n',
  'google-tv': '',
  'android-tv-stock': 'launcher|com.google.android.tvlauncher|Stock home\n',
};

TvCleaner make(FakeShell shell, [MemoryStore? store]) => TvCleaner(
  shell: shell,
  store: store ?? MemoryStore(),
  lists: () async => CleanLists(lists),
);

void main() {
  final xiaomi = {
    'com.android.systemui',
    'com.google.android.gms',
    'com.example.ads',
    'com.example.store',
    'com.xiaomi.analytics',
    'com.mitv.tvhome',
    'com.amazon.ads',
    'app.luma.tvlauncher',
  };

  test(
    'scan offers only listed, installed items for this device family',
    () async {
      final scan = await make(FakeShell(enabled: {...xiaomi})).scan();
      expect(scan.status, ShellStatus.ok);
      expect(scan.items.map((item) => item.package), [
        'com.example.ads',
        'com.xiaomi.analytics',
        'com.example.store',
      ]);
    },
  );

  test(
    'the old home screen is offered only when Luma is the Home app',
    () async {
      final scan = await make(
        FakeShell(enabled: {...xiaomi}, home: true),
      ).scan();
      expect(scan.items.last.package, 'com.mitv.tvhome');
      expect(scan.items.last.tier, CleanTier.launcher);
    },
  );

  test('protected packages are never switched off, even if asked', () async {
    final shell = FakeShell(enabled: {...xiaomi});
    final report = await make(shell).clean([
      'com.google.android.gms',
      'com.android.systemui',
      'app.luma.tvlauncher',
      'com.not.listed',
      'com.example.ads; reboot',
      'com.example.ads',
    ]);
    expect(report.changed, ['com.example.ads']);
    expect(shell.commands, ['pm disable-user --user 0 com.example.ads']);
  });

  test('clean then undo restores exactly what Luma switched off', () async {
    final shell = FakeShell(
      enabled: {...xiaomi},
      disabled: {'com.user.disabled'},
      locked: {'com.example.store'},
    );
    final store = MemoryStore();
    final cleaner = make(shell, store);
    final report = await cleaner.clean([
      'com.example.ads',
      'com.xiaomi.analytics',
      'com.example.store',
    ]);
    expect(report.changed, ['com.example.ads', 'com.xiaomi.analytics']);
    expect(report.failed, ['com.example.store']);
    expect((await cleaner.scan()).restorable, {
      'com.example.ads',
      'com.xiaomi.analytics',
    });
    final undo = await cleaner.restore();
    expect(undo.changed.toSet(), {'com.example.ads', 'com.xiaomi.analytics'});
    expect(shell.disabled, {'com.user.disabled'});
    expect(store.value, isEmpty);
  });

  test('connection problems are reported, not treated as a clean TV', () async {
    for (final status in [ShellStatus.unreachable, ShellStatus.unauthorized]) {
      final scan = await make(FakeShell(status: status)).scan();
      expect(scan.status, status);
      expect(scan.items, isEmpty);
    }
  });

  Future<void> pump(WidgetTester tester, TvCleaner cleaner) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TvCleanerDialog(cleaner: cleaner)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('dialog cleans the recommended items and reports the result', (
    tester,
  ) async {
    final shell = FakeShell(enabled: {...xiaomi});
    await pump(tester, make(shell));
    expect(find.text('Clean 2 selected'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('cleaner-item-com.example.store')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Clean 3 selected'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('cleaner-apply')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Switched off 3 items.'), findsOneWidget);
    expect(shell.disabled.length, 3);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dialog explains setup when debugging is off', (tester) async {
    final shell = FakeShell(status: ShellStatus.unreachable);
    await pump(tester, make(shell));
    await tester.tap(find.byKey(const ValueKey('cleaner-open-developer')));
    expect(shell.developerOpens, 1);
    shell
      ..status = ShellStatus.ok
      ..enabled.addAll(xiaomi);
    await tester.tap(find.byKey(const ValueKey('cleaner-retry')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('cleaner-apply')), findsOneWidget);
  });
}
