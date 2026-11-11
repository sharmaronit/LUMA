import 'package:luma/ronits/menu_dialog.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'focus_feedback.dart';
import 'launcher_home.dart';
import 'motion.dart';
import 'menu_undo.dart';

Future<void> showPreviewAppManager(
  BuildContext context,
  SharedPreferences preferences,
  List<LauncherAppItem> apps,
  VoidCallback onChanged,
) => showLumaDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _PreviewAppManager(
    preferences: preferences,
    apps: apps,
    onChanged: onChanged,
  ),
);

class _PreviewAppManager extends StatefulWidget {
  const _PreviewAppManager({
    required this.preferences,
    required this.apps,
    required this.onChanged,
  });
  final SharedPreferences preferences;
  final List<LauncherAppItem> apps;
  final VoidCallback onChanged;
  @override
  State<_PreviewAppManager> createState() => _PreviewAppManagerState();
}

class _PreviewAppManagerState extends State<_PreviewAppManager> {
  Future<void> actions(LauncherAppItem app) async {
    MenuUndo? undo;
    bool busy = false;
    String? error;
    await showLumaDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, update) {
          final favorites =
              widget.preferences.getStringList('preview_favorites') ??
              widget.apps.take(6).map((app) => app.id).toList();
          final hidden =
              widget.preferences.getStringList('preview_hidden') ?? <String>[];
          Future<void> save() async {
            await widget.preferences.setStringList(
              'preview_favorites',
              favorites,
            );
            await widget.preferences.setStringList('preview_hidden', hidden);
            widget.onChanged();
            if (context.mounted) update(() {});
            if (mounted) setState(() {});
          }

          Future<void> edit(Future<void> Function() action) async {
            if (busy) return;
            update(() {
              busy = true;
              error = null;
            });
            try {
              await action();
            } catch (_) {
              if (context.mounted)
                update(() => error = 'Could not save. Please try again.');
            } finally {
              if (context.mounted) update(() => busy = false);
            }
          }

          void refreshed() {
            widget.onChanged();
            if (context.mounted) update(() {});
            if (mounted) setState(() {});
          }

          final index = favorites.indexOf(app.id);
          return LumaMenuDialog(
            title: Text(app.name),
            content: SizedBox(
              width: 380,
              child: FocusHighlightLayer(
                menu: true,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (error != null) Text(error!),
                    TvMenuRow(
                      autofocus: true,
                      title: index >= 0 ? 'Remove favourite' : 'Add favourite',
                      onPressed: () => edit(() async {
                        if (index >= 0) {
                          favorites.remove(app.id);
                        } else {
                          favorites.add(app.id);
                        }
                        await save();
                        undo = index < 0
                            ? null
                            : MenuUndo(
                                'Removed ${app.name} from dock',
                                () async {
                                  final current =
                                      widget.preferences.getStringList(
                                        'preview_favorites',
                                      ) ??
                                      <String>[];
                                  if (!current.contains(app.id))
                                    current.insert(
                                      index.clamp(0, current.length),
                                      app.id,
                                    );
                                  await widget.preferences.setStringList(
                                    'preview_favorites',
                                    current,
                                  );
                                  refreshed();
                                },
                              );
                      }),
                    ),
                    TvMenuRow(
                      title: hidden.contains(app.id) ? 'Show app' : 'Hide app',
                      onPressed: () => edit(() async {
                        final hiding = !hidden.contains(app.id);
                        if (!hiding) {
                          hidden.remove(app.id);
                        } else {
                          hidden.add(app.id);
                        }
                        await save();
                        undo = !hiding
                            ? null
                            : MenuUndo('Hidden ${app.name}', () async {
                                final current =
                                    widget.preferences.getStringList(
                                      'preview_hidden',
                                    ) ??
                                    <String>[];
                                current.remove(app.id);
                                await widget.preferences.setStringList(
                                  'preview_hidden',
                                  current,
                                );
                                refreshed();
                              });
                      }),
                    ),
                    if (undo != null)
                      MenuUndoNotice(
                        undo: undo!,
                        onBusyChanged: (value) => update(() => busy = value),
                        onRestored: () => update(() => undo = null),
                      ),
                    if (index > 0)
                      TvMenuRow(
                        title: 'Move favourite left',
                        onPressed: () => edit(() async {
                          undo = null;
                          favorites.removeAt(index);
                          favorites.insert(index - 1, app.id);
                          await save();
                        }),
                      ),
                    if (index >= 0 && index < favorites.length - 1)
                      TvMenuRow(
                        title: 'Move favourite right',
                        onPressed: () => edit(() async {
                          undo = null;
                          favorites.removeAt(index);
                          favorites.insert(index + 1, app.id);
                          await save();
                        }),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Back'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final favorites =
        widget.preferences.getStringList('preview_favorites') ??
        widget.apps.take(6).map((app) => app.id).toList();
    final hidden = widget.preferences.getStringList('preview_hidden') ?? [];
    return LumaMenuDialog(
      title: const Text('Manage preview apps'),
      content: SizedBox(
        width: 480,
        height: 360,
        child: FocusHighlightLayer(
          menu: true,
          child: ListView(
            children: [
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Favourites scroll horizontally in the dock. Hidden apps can be restored here.',
                  style: TextStyle(fontSize: 13, color: Colors.white70),
                ),
              ),
              for (final app in widget.apps)
                TvMenuRow(
                  key: ValueKey('managed-${app.id}'),
                  autofocus: app == widget.apps.first,
                  title: app.name,
                  subtitle: hidden.contains(app.id)
                      ? 'Hidden'
                      : favorites.contains(app.id)
                      ? 'Favourite'
                      : 'Visible',
                  onPressed: () => actions(app),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

Future<void> showPreviewLayout(
  BuildContext context,
  SharedPreferences preferences,
  VoidCallback onChanged,
) => showLumaDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (context) => StatefulBuilder(
    builder: (context, update) {
      final columns = preferences.getInt('preview_grid_columns') ?? 6;
      return LumaMenuDialog(
        title: const Text('App grid layout'),
        content: SizedBox(
          width: 380,
          child: FocusHighlightLayer(
            menu: true,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Preview grid sizing here. On TV, Categories & layout also manages named collections, rows and sorting.',
                ),
                for (final count in [3, 4, 5, 6, 7, 8])
                  TvMenuRow(
                    autofocus: count == 3,
                    title: '$count columns',
                    selected: columns == count,
                    onPressed: () async {
                      await preferences.setInt('preview_grid_columns', count);
                      onChanged();
                      if (context.mounted) update(() {});
                    },
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      );
    },
  ),
);
