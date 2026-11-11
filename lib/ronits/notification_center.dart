import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../luma_channel.dart';
import 'focus_feedback.dart';
import 'glass_surface.dart';
import 'motion.dart';

/// One TV notification as reported by Android.
@immutable
class TvNotification {
  const TvNotification({
    required this.key,
    required this.packageName,
    required this.appName,
    required this.title,
    required this.text,
    required this.postTime,
    this.clearable = true,
    this.openable = true,
  });
  factory TvNotification.fromMap(Map<String, dynamic> map) => TvNotification(
    key: map['key'] as String,
    packageName: map['packageName'] as String? ?? '',
    appName: map['appName'] as String? ?? '',
    title: map['title'] as String? ?? '',
    text: map['text'] as String? ?? '',
    postTime: DateTime.fromMillisecondsSinceEpoch(
      (map['postTime'] as num?)?.toInt() ?? 0,
    ),
    clearable: map['clearable'] != false,
    openable: map['openable'] != false,
  );
  final String key, packageName, appName, title, text;
  final DateTime postTime;
  final bool clearable, openable;
}

/// Where notifications come from; the platform channel in the app, a fake in
/// tests.
abstract class NotificationSource {
  Stream<void> get changes;
  Future<bool> hasAccess();
  Future<List<TvNotification>> load();
  Future<bool> open(String key);
  Future<bool> dismiss(String key);
  Future<int> dismissAll();
  Future<bool> openAccessSettings();
}

class ChannelNotificationSource implements NotificationSource {
  ChannelNotificationSource([LumaChannel? channel])
    : _channel = channel ?? LumaChannel();
  final LumaChannel _channel;
  @override
  Stream<void> get changes => _channel.notificationEvents;
  @override
  Future<bool> hasAccess() => _channel.notificationAccess();
  @override
  Future<List<TvNotification>> load() async => [
    for (final map in await _channel.getNotifications())
      TvNotification.fromMap(map),
  ];
  @override
  Future<bool> open(String key) => _channel.openNotification(key);
  @override
  Future<bool> dismiss(String key) => _channel.dismissNotification(key);
  @override
  Future<int> dismissAll() => _channel.dismissAllNotifications();
  @override
  Future<bool> openAccessSettings() =>
      _channel.openNotificationAccessSettings();
}

/// The adb command that grants access on TVs without a settings screen for it.
String notificationAccessCommand(String packageName) =>
    'adb shell cmd notification allow_listener '
    '$packageName/app.luma.tvlauncher.LumaNotificationListener';

String relativeTime(DateTime time, [DateTime? now]) {
  final elapsed = (now ?? DateTime.now()).difference(time);
  if (elapsed.inMinutes < 1) return 'now';
  if (elapsed.inHours < 1) return '${elapsed.inMinutes} min ago';
  if (elapsed.inDays < 1) return '${elapsed.inHours} h ago';
  if (elapsed.inDays < 7) return '${elapsed.inDays} d ago';
  return '${time.day}/${time.month}';
}

Future<void> showNotificationCenter(
  BuildContext context, {
  required NotificationSource source,
  required String packageName,
  GlassBlurBuilder? blurBuilder,
}) => showLumaDialog<void>(
  context: context,
  fromTop: true,
  // A small card under the top bar, only as tall as what it shows.
  builder: (_) => Align(
    alignment: Alignment.topRight,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 72, 24, 16),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 320,
          maxHeight: MediaQuery.sizeOf(context).height * .58,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: GlassSurface(
            mode: LauncherMaterial.minimal,
            sheet: true,
            frostedSheet: true,
            radius: 22,
            blurBuilder: blurBuilder,
            child: NotificationCenter(source: source, packageName: packageName),
          ),
        ),
      ),
    ),
  ),
);

class NotificationCenter extends StatefulWidget {
  const NotificationCenter({
    super.key,
    required this.source,
    required this.packageName,
  });
  final NotificationSource source;
  final String packageName;
  @override
  State<NotificationCenter> createState() => _NotificationCenterState();
}

class _NotificationCenterState extends State<NotificationCenter> {
  bool? access;
  List<TvNotification> items = const [];
  bool settingsUnavailable = false;
  StreamSubscription<void>? _changes;

  @override
  void initState() {
    super.initState();
    _changes = widget.source.changes.listen((_) => refresh());
    refresh();
  }

  @override
  void dispose() {
    _changes?.cancel();
    super.dispose();
  }

  Future<void> refresh() async {
    try {
      final granted = await widget.source.hasAccess();
      final loaded = granted ? await widget.source.load() : <TvNotification>[];
      if (!mounted) return;
      setState(() {
        access = granted;
        items = loaded;
      });
    } catch (_) {
      if (mounted) setState(() => access = false);
    }
  }

  Future<void> _open(TvNotification item) async {
    final opened = await widget.source.open(item.key);
    if (opened && mounted) Navigator.of(context).maybePop();
  }

  Future<void> _dismiss(TvNotification item) async {
    await widget.source.dismiss(item.key);
    if (mounted) setState(() => items = [...items]..remove(item));
  }

  Future<void> _requestAccess() async {
    final opened = await widget.source.openAccessSettings();
    if (!opened && mounted) setState(() => settingsUnavailable = true);
  }

  @override
  Widget build(BuildContext context) {
    final palette = MinimalPalette.of(context);
    final clearable = items.where((n) => n.clearable).length;
    return FocusTraversalGroup(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Notifications',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
                if (clearable > 0)
                  TextButton(
                    key: const ValueKey('notifications-clear-all'),
                    onPressed: () async {
                      await widget.source.dismissAll();
                      await refresh();
                    },
                    child: const Text('Clear all'),
                  ),
              ],
            ),
          ),
          Flexible(child: _body(palette)),
        ],
      ),
    );
  }

  Widget _body(MinimalPalette palette) {
    if (access == null) return const SizedBox.shrink();
    if (access == false) {
      return _Message(
        icon: Icons.notifications_off_rounded,
        title: 'Allow notification access',
        body: settingsUnavailable
            ? 'This TV has no settings screen for notification access. '
                  'From a computer, run:\n\n'
                  '${notificationAccessCommand(widget.packageName)}'
            : 'Luma needs Android\'s notification access to show your TV '
                  'notifications here. Nothing leaves your TV.',
        action: settingsUnavailable
            ? null
            : TextButton(
                key: const ValueKey('notifications-allow-access'),
                autofocus: true,
                onPressed: _requestAccess,
                child: const Text('Open settings'),
              ),
      );
    }
    if (items.isEmpty) {
      return const _Message(
        icon: Icons.notifications_none_rounded,
        title: 'You\'re all caught up',
        body: 'New notifications from your apps will appear here.',
      );
    }
    return FocusHighlightLayer(
      menu: true,
      child: ListView.builder(
        key: const ValueKey('notification-list'),
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
        itemCount: items.length,
        itemBuilder: (_, index) => _NotificationRow(
          key: ValueKey('notification-${items[index].key}'),
          item: items[index],
          autofocus: index == 0,
          onOpen: () => _open(items[index]),
          onDismiss: items[index].clearable
              ? () => _dismiss(items[index])
              : null,
        ),
      ),
    );
  }
}

class _NotificationRow extends StatelessWidget {
  const _NotificationRow({
    super.key,
    required this.item,
    required this.onOpen,
    this.onDismiss,
    this.autofocus = false,
  });
  final TvNotification item;
  final VoidCallback onOpen;
  final VoidCallback? onDismiss;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final palette = MinimalPalette.of(context);
    return CallbackShortcuts(
      bindings: {
        // Menu dismisses the focused notification, like long-press elsewhere.
        if (onDismiss != null)
          const SingleActivator(LogicalKeyboardKey.contextMenu): onDismiss!,
      },
      child: Row(
        children: [
          Expanded(
            child: TvMenuRow(
              autofocus: autofocus,
              icon: Icons.notifications_rounded,
              title: item.title.isEmpty ? item.appName : item.title,
              subtitle: [
                '${item.appName} · ${relativeTime(item.postTime)}',
                if (item.text.isNotEmpty) item.text,
              ].join('\n'),
              onPressed: onOpen,
            ),
          ),
          if (onDismiss != null)
            IconButton(
              tooltip: 'Dismiss',
              onPressed: onDismiss,
              color: palette.muted,
              icon: const Icon(Icons.close_rounded),
            ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.body,
    this.action,
  });
  final IconData icon;
  final String title, body;
  final Widget? action;
  @override
  Widget build(BuildContext context) {
    final palette = MinimalPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: palette.muted),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SelectableText(
            body,
            style: TextStyle(fontSize: 11.5, height: 1.4, color: palette.muted),
          ),
          if (action != null) ...[const SizedBox(height: 8), action!],
        ],
      ),
    );
  }
}
