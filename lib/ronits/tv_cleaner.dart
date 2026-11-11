// Luma
// Copyright (C) 2026 Ronit Sharma
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'focus_feedback.dart';
import 'menu_dialog.dart';
import 'motion.dart';

/// How risky turning an item off is. Matches the tiers in
/// scripts/debloat/lists, which the PC scripts share.
enum CleanTier { safe, aggressive, launcher }

@immutable
class CleanItem {
  const CleanItem(this.tier, this.package, this.description);
  final CleanTier tier;
  final String package, description;
}

/// The lists bundled with the app: one text per device family.
class CleanLists {
  CleanLists(Map<String, String> texts) {
    for (final entry in texts.entries) {
      final items = <CleanItem>[];
      for (final raw in entry.value.split('\n')) {
        final line = raw.trim();
        if (line.isEmpty || line.startsWith('#')) continue;
        final parts = line.split('|');
        if (parts.length < 2) continue;
        final package = parts[1].trim();
        final description = parts.length > 2 ? parts[2].trim() : package;
        switch (parts[0].trim()) {
          case 'never':
            never.add(package);
          case 'safe':
            items.add(CleanItem(CleanTier.safe, package, description));
          case 'aggressive':
            items.add(CleanItem(CleanTier.aggressive, package, description));
          case 'launcher':
            items.add(CleanItem(CleanTier.launcher, package, description));
        }
      }
      profiles[entry.key] = items;
    }
  }

  static const profileNames = [
    'common',
    'google-tv',
    'android-tv-stock',
    'xiaomi-patchwall',
    'fire-tv',
  ];

  static Future<CleanLists> bundled() async => CleanLists({
    for (final name in profileNames)
      name: await rootBundle.loadString('scripts/debloat/lists/$name.txt'),
  });

  final profiles = <String, List<CleanItem>>{};

  /// Packages no list may ever turn off, whatever device they came from.
  final never = <String>{};

  /// The device families that match what is installed, as the PC script does.
  List<String> profilesFor(Set<String> installed) {
    final found = <String>[
      if (installed.contains('com.amazon.tv.launcher')) 'fire-tv',
      if (installed.contains('com.google.android.apps.tv.launcherx'))
        'google-tv',
      if (installed.contains('com.mitv.tvhome') ||
          installed.contains('com.mitv.tvhome.atv'))
        'xiaomi-patchwall',
    ];
    if (installed.contains('com.google.android.tvlauncher') ||
        installed.contains('com.google.android.leanbacklauncher') ||
        found.isEmpty) {
      found.add('android-tv-stock');
    }
    return ['common', ...found];
  }
}

enum ShellStatus { ok, unreachable, unauthorized, error }

@immutable
class ShellResult {
  const ShellResult(this.status, [this.outputs = const []]);
  final ShellStatus status;
  final List<String> outputs;
}

/// Runs commands on the TV; the platform channel in the app, a fake in tests.
abstract class CleanerShell {
  /// [waitForApproval] gives the user time to answer the TV's debugging prompt.
  Future<ShellResult> run(
    List<String> commands, {
    bool waitForApproval = false,
  });
  Future<void> openDeveloperOptions();

  /// Whether the Home button already opens Luma.
  Future<bool> lumaIsHome();
}

class ChannelCleanerShell implements CleanerShell {
  const ChannelCleanerShell();
  static const _channel = MethodChannel('app.luma.tvlauncher/method');
  @override
  Future<ShellResult> run(
    List<String> commands, {
    bool waitForApproval = false,
  }) async {
    try {
      final value = await _channel.invokeMapMethod<String, dynamic>(
        'cleanerRun',
        {'commands': commands, 'approvalMs': waitForApproval ? 60000 : 8000},
      );
      final status = ShellStatus.values.firstWhere(
        (item) => item.name == value?['status'],
        orElse: () => ShellStatus.error,
      );
      return ShellResult(status, [
        for (final output in value?['outputs'] as List? ?? const []) '$output',
      ]);
    } catch (_) {
      return const ShellResult(ShellStatus.error);
    }
  }

  @override
  Future<bool> lumaIsHome() async {
    try {
      final status = await _channel.invokeMapMethod<String, dynamic>(
        'getSetupStatus',
      );
      return status?['home'] == true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> openDeveloperOptions() async {
    try {
      await _channel.invokeMethod<void>('openDeveloperOptions');
    } catch (_) {
      /* Some TVs hide this screen; the steps on screen still apply. */
    }
  }
}

/// Remembers what Luma turned off, so only that is ever turned back on.
abstract class CleanerStore {
  Future<Set<String>> load();
  Future<void> save(Set<String> packages);
}

class PrefsCleanerStore implements CleanerStore {
  static const _key = 'luma_cleaner_disabled';
  @override
  Future<Set<String>> load() async =>
      (await SharedPreferences.getInstance()).getStringList(_key)?.toSet() ??
      {};
  @override
  Future<void> save(Set<String> packages) async =>
      (await SharedPreferences.getInstance()).setStringList(
        _key,
        packages.toList()..sort(),
      );
}

@immutable
class CleanScan {
  const CleanScan(
    this.status, {
    this.items = const [],
    this.restorable = const {},
  });
  final ShellStatus status;

  /// Listed items that are installed and still switched on.
  final List<CleanItem> items;

  /// Items Luma turned off earlier that are still off.
  final Set<String> restorable;
}

@immutable
class CleanReport {
  const CleanReport(
    this.status, {
    this.changed = const [],
    this.failed = const [],
  });
  final ShellStatus status;
  final List<String> changed, failed;
}

class TvCleaner {
  TvCleaner({
    CleanerShell? shell,
    CleanerStore? store,
    Future<CleanLists> Function()? lists,
  }) : shell = shell ?? const ChannelCleanerShell(),
       store = store ?? PrefsCleanerStore(),
       _lists = lists ?? CleanLists.bundled;
  final CleanerShell shell;
  final CleanerStore store;
  final Future<CleanLists> Function() _lists;

  static const _ownPackage = 'app.luma.tvlauncher';
  static final _packageName = RegExp(r'^[A-Za-z0-9._]+$');

  static Set<String> _packages(String output) => {
    for (final line in output.split('\n'))
      if (line.trim().startsWith('package:')) line.trim().substring(8),
  };

  bool _protected(CleanLists lists, String package) =>
      lists.never.contains(package) ||
      package.startsWith(_ownPackage) ||
      !_packageName.hasMatch(package);

  /// Finds what can be turned off. The stock home screen is only offered when
  /// Luma is the Home app, so the TV always keeps a working Home button.
  Future<CleanScan> scan({bool waitForApproval = false}) async {
    final result = await shell.run([
      'pm list packages -e',
      'pm list packages -d',
    ], waitForApproval: waitForApproval);
    if (result.status != ShellStatus.ok || result.outputs.length < 2) {
      return CleanScan(
        result.status == ShellStatus.ok ? ShellStatus.error : result.status,
      );
    }
    final enabled = _packages(result.outputs[0]);
    final disabled = _packages(result.outputs[1]);
    if (enabled.isEmpty) return const CleanScan(ShellStatus.error);
    final lists = await _lists();
    final lumaIsHome = await shell.lumaIsHome();
    final seen = <String>{};
    final items = <CleanItem>[
      for (final profile in lists.profilesFor({...enabled, ...disabled}))
        for (final item in lists.profiles[profile] ?? const <CleanItem>[])
          if (enabled.contains(item.package) &&
              !_protected(lists, item.package) &&
              (item.tier != CleanTier.launcher || lumaIsHome) &&
              seen.add(item.package))
            item,
    ]..sort((a, b) => a.tier.index.compareTo(b.tier.index));
    final stored = await store.load();
    return CleanScan(
      ShellStatus.ok,
      items: items,
      restorable: stored.intersection(disabled),
    );
  }

  /// Turns [packages] off for the current user. Nothing is uninstalled.
  Future<CleanReport> clean(Iterable<String> packages) async {
    final lists = await _lists();
    final listed = {
      for (final items in lists.profiles.values)
        for (final item in items) item.package,
    };
    final targets = [
      for (final package in packages.toSet())
        if (listed.contains(package) && !_protected(lists, package)) package,
    ];
    if (targets.isEmpty) return const CleanReport(ShellStatus.ok);
    final result = await shell.run([
      for (final package in targets) 'pm disable-user --user 0 $package',
    ]);
    if (result.status != ShellStatus.ok) return CleanReport(result.status);
    final changed = <String>[], failed = <String>[];
    for (var i = 0; i < targets.length; i++) {
      final output = i < result.outputs.length ? result.outputs[i] : '';
      (output.contains('new state: disabled') ? changed : failed).add(
        targets[i],
      );
    }
    await store.save({...await store.load(), ...changed});
    return CleanReport(ShellStatus.ok, changed: changed, failed: failed);
  }

  /// Turns back on everything Luma turned off.
  Future<CleanReport> restore() async {
    final stored = (await store.load()).where(_packageName.hasMatch).toList();
    if (stored.isEmpty) return const CleanReport(ShellStatus.ok);
    final result = await shell.run([
      for (final package in stored) 'pm enable $package',
    ]);
    if (result.status != ShellStatus.ok) return CleanReport(result.status);
    final changed = <String>[], failed = <String>[];
    for (var i = 0; i < stored.length; i++) {
      final output = i < result.outputs.length ? result.outputs[i] : '';
      (output.contains('new state: enabled') ? changed : failed).add(stored[i]);
    }
    await store.save(failed.toSet());
    return CleanReport(ShellStatus.ok, changed: changed, failed: failed);
  }
}

String cleanTierLabel(CleanTier tier) => switch (tier) {
  CleanTier.safe => 'Recommended',
  CleanTier.aggressive => 'Optional',
  CleanTier.launcher => 'Old home screen · turn back on before removing Luma',
};

Future<void> showTvCleaner(BuildContext context, {TvCleaner? cleaner}) =>
    showLumaDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => TvCleanerDialog(cleaner: cleaner ?? TvCleaner()),
    );

enum _Stage { checking, setup, approve, choose, working, done, failed }

class TvCleanerDialog extends StatefulWidget {
  const TvCleanerDialog({super.key, required this.cleaner});
  final TvCleaner cleaner;
  @override
  State<TvCleanerDialog> createState() => _TvCleanerDialogState();
}

class _TvCleanerDialogState extends State<TvCleanerDialog> {
  var stage = _Stage.checking;
  var scanResult = const CleanScan(ShellStatus.ok);
  final selected = <String>{};
  // The main row of each step. Focus is moved to it by hand because the Back
  // button holds focus while the TV is being checked.
  final primary = FocusNode(debugLabel: 'Cleaner primary');
  String message = '';

  @override
  void dispose() {
    primary.dispose();
    super.dispose();
  }

  void focusPrimary() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted && primary.context != null) primary.requestFocus();
  });

  @override
  void initState() {
    super.initState();
    check();
  }

  Future<void> check() async {
    setState(() => stage = _Stage.checking);
    final value = await widget.cleaner.scan(waitForApproval: true);
    if (!mounted) return;
    setState(() {
      scanResult = value;
      selected
        ..clear()
        ..addAll([
          for (final item in value.items)
            if (item.tier == CleanTier.safe) item.package,
        ]);
      stage = switch (value.status) {
        ShellStatus.ok => _Stage.choose,
        ShellStatus.unreachable => _Stage.setup,
        ShellStatus.unauthorized => _Stage.approve,
        ShellStatus.error => _Stage.failed,
      };
    });
    focusPrimary();
  }

  Future<void> finish(
    Future<CleanReport> Function() action,
    String verb,
  ) async {
    setState(() => stage = _Stage.working);
    final report = await action();
    if (!mounted) return;
    setState(() {
      if (report.status != ShellStatus.ok) {
        stage = report.status == ShellStatus.unreachable
            ? _Stage.setup
            : report.status == ShellStatus.unauthorized
            ? _Stage.approve
            : _Stage.failed;
        return;
      }
      final count = report.changed.length;
      message =
          '$verb $count ${count == 1 ? 'item' : 'items'}.'
          '${report.failed.isEmpty ? '' : ' ${report.failed.length} could not be changed; your TV protects them.'}'
          '\n\nRestart your TV to finish. For safety, you can now switch USB debugging off again in Developer options.';
      stage = _Stage.done;
    });
    focusPrimary();
  }

  Widget text(String value) =>
      Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(value));

  List<Widget> body() => switch (stage) {
    _Stage.checking => [
      text(
        'Checking your TV…\n\nIf your TV asks "Allow USB debugging?", tick "Always allow from this computer" and choose Allow.',
      ),
    ],
    _Stage.working => [text('Working… this takes a few seconds.')],
    _Stage.setup => [
      text(
        'Luma needs USB debugging switched on to clean this TV. You only do this once:\n\n'
        '1. Open Settings > Device Preferences > About and press OK on "Build" seven times.\n'
        '2. Go back to Developer options and switch on USB debugging (on some TVs: Network debugging).\n'
        '3. Come back here and choose Try again.\n\n'
        'Some newer TVs only offer "Wireless debugging" with pairing. On those, use the computer script from the Luma guide.',
      ),
      TvMenuRow(
        key: const ValueKey('cleaner-open-developer'),
        autofocus: true,
        focusNode: primary,
        icon: Icons.developer_mode_rounded,
        title: 'Open developer options',
        onPressed: widget.cleaner.shell.openDeveloperOptions,
      ),
      TvMenuRow(
        key: const ValueKey('cleaner-retry'),
        icon: Icons.refresh_rounded,
        title: 'Try again',
        onPressed: check,
      ),
    ],
    _Stage.approve => [
      text(
        'Your TV did not give Luma permission. Choose Try again, then tick "Always allow from this computer" and choose Allow on the "Allow USB debugging?" prompt.',
      ),
      TvMenuRow(
        key: const ValueKey('cleaner-retry'),
        autofocus: true,
        focusNode: primary,
        icon: Icons.refresh_rounded,
        title: 'Try again',
        onPressed: check,
      ),
    ],
    _Stage.failed => [
      text(
        'Something went wrong while talking to your TV. Nothing was changed.',
      ),
      TvMenuRow(
        key: const ValueKey('cleaner-retry'),
        autofocus: true,
        focusNode: primary,
        icon: Icons.refresh_rounded,
        title: 'Try again',
        onPressed: check,
      ),
    ],
    _Stage.done => [
      text(message),
      TvMenuRow(
        key: const ValueKey('cleaner-done'),
        autofocus: true,
        focusNode: primary,
        icon: Icons.check_rounded,
        title: 'Done',
        onPressed: () => Navigator.pop(context),
      ),
    ],
    _Stage.choose => [
      text(
        scanResult.items.isEmpty
            ? 'Your TV is already clean: nothing on Luma\'s list is switched on.'
            : 'Luma found ${scanResult.items.length} ${scanResult.items.length == 1 ? 'thing' : 'things'} it can switch off: ads, tracking and preloaded extras. '
                  'Nothing is deleted, and you can undo it here at any time.',
      ),
      if (scanResult.items.isNotEmpty)
        TvMenuRow(
          key: const ValueKey('cleaner-apply'),
          autofocus: true,
          focusNode: primary,
          icon: Icons.cleaning_services_rounded,
          title: selected.isEmpty
              ? 'Nothing selected'
              : 'Clean ${selected.length} selected',
          onPressed: () {
            if (selected.isEmpty) return;
            final packages = selected.toList();
            finish(() => widget.cleaner.clean(packages), 'Switched off');
          },
        ),
      if (scanResult.restorable.isNotEmpty)
        TvMenuRow(
          key: const ValueKey('cleaner-restore'),
          autofocus: scanResult.items.isEmpty,
          focusNode: scanResult.items.isEmpty ? primary : null,
          icon: Icons.undo_rounded,
          title: 'Undo earlier cleaning',
          subtitle:
              'Switch ${scanResult.restorable.length} ${scanResult.restorable.length == 1 ? 'item' : 'items'} back on',
          onPressed: () => finish(widget.cleaner.restore, 'Switched back on'),
        ),
      for (final item in scanResult.items)
        TvMenuRow(
          key: ValueKey('cleaner-item-${item.package}'),
          title: item.description,
          subtitle: '${cleanTierLabel(item.tier)} · ${item.package}',
          selected: selected.contains(item.package),
          trailing: Icon(
            selected.contains(item.package)
                ? Icons.check_circle_rounded
                : Icons.circle_outlined,
          ),
          onPressed: () => setState(() {
            if (!selected.remove(item.package)) selected.add(item.package);
          }),
        ),
    ],
  };

  @override
  Widget build(BuildContext context) => LumaMenuDialog(
    title: const Text('Clean my TV'),
    content: FocusHighlightLayer(
      menu: true,
      child: Column(mainAxisSize: MainAxisSize.min, children: body()),
    ),
    actions: [
      TextButton(
        // Keeps the remote working while there are no rows to focus.
        autofocus: stage == _Stage.checking || stage == _Stage.working,
        onPressed: () => Navigator.pop(context),
        child: const Text('Back'),
      ),
    ],
  );
}
