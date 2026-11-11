// Luma
// Copyright (C) 2026 Ronit Sharma
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'tv_icon_pack.dart';

/// One app in the Recent apps panel.
@immutable
class RecentApp {
  const RecentApp({required this.id, required this.name, this.artwork});
  final String id, name;

  /// The app's banner, or its icon when it has no banner.
  final Future<ImageProvider?> Function()? artwork;
}

@immutable
class TvMemory {
  const TvMemory(this.total, this.available);
  final int total, available;
  int get used => (total - available).clamp(0, total);
  double get fraction => total <= 0 ? 0 : used / total;
  static String _gb(int bytes) =>
      (bytes / (1024 * 1024 * 1024)).toStringAsFixed(1);
  String get label => 'RAM ${_gb(used)} GB used of ${_gb(total)} GB';
  String get shortLabel => '${_gb(used)} of ${_gb(total)} GB in use';
}

/// How well an app could be closed.
enum CloseResult {
  /// Stopped completely.
  stopped,

  /// Android was asked to free its background memory.
  freed,
  refused,
}

/// Memory and app closing; the platform channel in the app, a fake in tests.
abstract class RecentAppsSystem {
  Future<TvMemory?> memory();
  Future<CloseResult> close(String package);
}

class ChannelRecentAppsSystem implements RecentAppsSystem {
  const ChannelRecentAppsSystem();
  static const _channel = MethodChannel('app.luma.tvlauncher/method');
  @override
  Future<TvMemory?> memory() async {
    try {
      final value = await _channel.invokeMapMethod<String, dynamic>(
        'getMemoryInfo',
      );
      final total = (value?['total'] as num?)?.toInt() ?? 0;
      final available = (value?['available'] as num?)?.toInt() ?? 0;
      return total > 0 ? TvMemory(total, available) : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<CloseResult> close(String package) async {
    try {
      final value = await _channel.invokeMethod<String>('closeApp', package);
      return CloseResult.values.firstWhere(
        (item) => item.name == value,
        orElse: () => CloseResult.refused,
      );
    } catch (_) {
      return CloseResult.refused;
    }
  }
}

/// Full-screen row of recently opened apps. OK opens an app, Up closes it,
/// Back leaves. Resolves to the id of the app to open, if any.
Future<String?> showRecentApps(
  BuildContext context, {
  required List<RecentApp> apps,
  RecentAppsSystem system = const ChannelRecentAppsSystem(),
  ValueChanged<String>? onClosed,
}) => showGeneralDialog<String>(
  context: context,
  barrierDismissible: false,
  barrierColor: const Color(0xd90b0d12),
  transitionDuration: const Duration(milliseconds: 180),
  pageBuilder: (_, _, _) =>
      RecentAppsPanel(apps: apps, system: system, onClosed: onClosed),
  transitionBuilder: (_, animation, _, child) =>
      FadeTransition(opacity: animation, child: child),
);

class RecentAppsPanel extends StatefulWidget {
  const RecentAppsPanel({
    super.key,
    required this.apps,
    required this.system,
    this.onClosed,
  });
  final List<RecentApp> apps;
  final RecentAppsSystem system;

  /// Told the id of each app that was closed, so it stays out of the list
  /// until it is opened again.
  final ValueChanged<String>? onClosed;
  @override
  State<RecentAppsPanel> createState() => _RecentAppsPanelState();
}

class _RecentAppsPanelState extends State<RecentAppsPanel> {
  late final apps = [...widget.apps];
  late final nodes = {
    for (final app in apps) app.id: FocusNode(debugLabel: 'Recent ${app.name}'),
  };
  final scroll = ScrollController();
  TvMemory? memory;
  String? note;
  String? closing;

  @override
  void initState() {
    super.initState();
    _refreshMemory();
  }

  @override
  void dispose() {
    for (final node in nodes.values) {
      node.dispose();
    }
    scroll.dispose();
    super.dispose();
  }

  Future<void> _refreshMemory() async {
    final value = await widget.system.memory();
    if (mounted) setState(() => memory = value);
  }

  Future<void> _close(RecentApp app) async {
    if (closing != null) return;
    setState(() => closing = app.id);
    final result = await widget.system.close(app.id);
    if (!mounted) return;
    final index = apps.indexOf(app);
    setState(() {
      closing = null;
      if (result == CloseResult.refused) {
        note = 'Your TV would not let Luma close ${app.name}.';
        return;
      }
      apps.remove(app);
      widget.onClosed?.call(app.id);
      note = result == CloseResult.stopped
          ? '${app.name} closed.'
          : '${app.name}: memory freed. Allow USB debugging in Clean my TV to close apps fully.';
    });
    if (result != CloseResult.refused && apps.isNotEmpty) {
      final next = apps[index.clamp(0, apps.length - 1)];
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) nodes[next.id]?.requestFocus();
      });
    }
    await _refreshMemory();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final cardWidth = size.width * .27, cardHeight = cardWidth * 9 / 16;
    return Material(
      type: MaterialType.transparency,
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: size.height * .06),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.symmetric(horizontal: size.width * .05),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Recent apps',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (memory != null) _MemoryPill(memory: memory!),
                  ],
                ),
              ),
              Expanded(
                child: apps.isEmpty
                    ? Center(
                        child: Focus(
                          autofocus: true,
                          child: Text(
                            note ??
                                'No recent apps yet. Apps you open from Luma appear here.',
                            key: const ValueKey('recent-empty'),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : Center(
                        child: SizedBox(
                          height: cardHeight * 1.12 + 44,
                          child: ListView.separated(
                            key: const ValueKey('recent-list'),
                            controller: scroll,
                            scrollDirection: Axis.horizontal,
                            clipBehavior: Clip.none,
                            padding: EdgeInsets.symmetric(
                              horizontal: size.width * .05,
                            ),
                            itemCount: apps.length,
                            separatorBuilder: (_, _) =>
                                SizedBox(width: size.width * .025),
                            itemBuilder: (_, index) {
                              final app = apps[index];
                              return _RecentCard(
                                key: ValueKey('recent-${app.id}'),
                                app: app,
                                node: nodes[app.id]!,
                                autofocus: index == 0,
                                width: cardWidth,
                                height: cardHeight,
                                busy: closing == app.id,
                                onOpen: () => Navigator.pop(context, app.id),
                                onClose: () => _close(app),
                              );
                            },
                          ),
                        ),
                      ),
              ),
              Center(
                child: Text(
                  apps.isEmpty
                      ? 'Press Back to return'
                      : note ?? 'Press ▲ on an app to close it',
                  key: const ValueKey('recent-hint'),
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withValues(alpha: .78),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Memory in use, as one quiet line of text.
class _MemoryPill extends StatelessWidget {
  const _MemoryPill({required this.memory});
  final TvMemory memory;
  @override
  Widget build(BuildContext context) => Text.rich(
    key: const ValueKey('recent-memory'),
    TextSpan(
      children: [
        TextSpan(
          text: 'Memory  ',
          style: TextStyle(color: Colors.white.withValues(alpha: .55)),
        ),
        TextSpan(text: memory.shortLabel),
      ],
    ),
    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
  );
}

class _RecentCard extends StatefulWidget {
  const _RecentCard({
    super.key,
    required this.app,
    required this.node,
    required this.autofocus,
    required this.width,
    required this.height,
    required this.busy,
    required this.onOpen,
    required this.onClose,
  });
  final RecentApp app;
  final FocusNode node;
  final bool autofocus, busy;
  final double width, height;
  final VoidCallback onOpen, onClose;
  @override
  State<_RecentCard> createState() => _RecentCardState();
}

class _RecentCardState extends State<_RecentCard> {
  late final Future<ImageProvider?> artwork = () async {
    final pack = tvIconPackArtwork(widget.app.id, widget.app.name);
    if (pack != null) return pack;
    try {
      return await widget.app.artwork?.call();
    } catch (_) {
      return null;
    }
  }();
  bool focused = false;

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: widget.node,
    autofocus: widget.autofocus,
    onFocusChange: (value) {
      setState(() => focused = value);
      if (value) {
        Scrollable.ensureVisible(
          context,
          alignment: .5,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
        );
      }
    },
    onKeyEvent: (_, event) {
      if (event is! KeyDownEvent) return KeyEventResult.ignored;
      final key = event.logicalKey;
      if (key == LogicalKeyboardKey.arrowUp) {
        widget.onClose();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.select ||
          key == LogicalKeyboardKey.enter ||
          key == LogicalKeyboardKey.numpadEnter ||
          key == LogicalKeyboardKey.gameButtonA) {
        widget.onOpen();
        return KeyEventResult.handled;
      }
      // Nothing is below the row.
      if (key == LogicalKeyboardKey.arrowDown) return KeyEventResult.handled;
      return KeyEventResult.ignored;
    },
    child: GestureDetector(
      onTap: widget.onOpen,
      child: SizedBox(
        width: widget.width,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              height: 32,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 120),
                opacity: focused ? 1 : .7,
                child: Text(
                  widget.app.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: focused ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
            ),
            // The lift is a plain transform, so it never repaints the card.
            AnimatedScale(
              scale: focused ? 1.08 : 1,
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOutCubic,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 120),
                opacity: widget.busy ? .4 : 1,
                child: Container(
                  width: widget.width,
                  height: widget.height,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: const Color(0xff1c2028),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: focused ? .9 : .14),
                      width: focused ? 2 : 1,
                    ),
                  ),
                  child: FutureBuilder<ImageProvider?>(
                    future: artwork,
                    builder: (_, snapshot) => snapshot.data == null
                        ? Center(
                            child: Text(
                              widget.app.name.characters.firstOrNull
                                      ?.toUpperCase() ??
                                  '',
                              style: const TextStyle(
                                fontSize: 40,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          )
                        : Image(
                            image: ResizeImage.resizeIfNeeded(
                              (widget.width *
                                      MediaQuery.devicePixelRatioOf(context) *
                                      1.08)
                                  .round(),
                              null,
                              snapshot.data!,
                            ),
                            fit: BoxFit.cover,
                            gaplessPlayback: true,
                            errorBuilder: (_, _, _) => const SizedBox.shrink(),
                          ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
