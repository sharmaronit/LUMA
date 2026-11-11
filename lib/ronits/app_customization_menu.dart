part of 'launcher_home.dart';

extension _AppCustomizationMenus on _LauncherHomeState {
  Future<void> _fontSettings() async {
    final store = _customization;
    if (store == null) return;
    await showLumaDialog<void>(
      context: context,
      builder: (dialogContext) => ListenableBuilder(
        listenable: store,
        builder: (_, __) => LumaMenuDialog(
          title: const Text('Font style'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final font in launcherFonts)
                TvMenuRow(
                  key: ValueKey('font-style-${font.id}'),
                  autofocus: font.id == store.fontStyle,
                  title: font.name,
                  subtitle: font.familyLabel,
                  selected: store.fontStyle == font.id,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Aa',
                        style: TextStyle(fontFamily: font.family, fontSize: 26),
                      ),
                      const SizedBox(width: 16),
                      if (store.fontStyle == font.id)
                        const Icon(Icons.check_rounded),
                    ],
                  ),
                  onPressed: () async {
                    try {
                      await store.setFontStyle(font.id);
                    } catch (_) {
                      if (mounted) _message('Could not save font style.');
                    }
                  },
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Back'),
            ),
          ],
        ),
      ),
    );
  }

  String _shortcutLabel(String? action) {
    if (action == null) return 'Not assigned';
    if (action == 'search') return 'Search';
    if (action == 'voice') return 'Voice search';
    if (action == 'apps') return 'All apps';
    return widget.apps
            .where((app) => action == 'app:${app.id}')
            .firstOrNull
            ?.name ??
        'App unavailable';
  }

  Future<void> _shortcutSettings() async {
    final store = _customization;
    if (store == null) return;
    await showLumaDialog<void>(
      context: context,
      builder: (dialogContext) => AnimatedBuilder(
        animation: store,
        builder: (_, __) => LumaMenuDialog(
          title: const Text('Remote shortcuts'),
          content: FocusHighlightLayer(
            menu: true,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text(
                    'Works on Home when your remote sends the chosen key. Home, Back and navigation stay unchanged.',
                  ),
                ),
                for (final key in remoteShortcutKeys.keys)
                  TvMenuRow(
                    key: ValueKey('remote-shortcut-$key'),
                    autofocus: key == remoteShortcutKeys.keys.first,
                    title: key,
                    subtitle: _shortcutLabel(store.shortcuts[key]),
                    onPressed: () async {
                      final action = await showLumaDialog<String>(
                        context: dialogContext,
                        builder: (pickerContext) => LumaMenuDialog(
                          title: Text('$key shortcut'),
                          content: FocusHighlightLayer(
                            menu: true,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                for (final entry in <String, String>{
                                  '__none': 'Not assigned',
                                  'search': 'Search',
                                  'voice': 'Voice search',
                                  'apps': 'All apps',
                                  for (final app in widget.apps)
                                    'app:${app.id}': app.name,
                                }.entries)
                                  TvMenuRow(
                                    key: ValueKey(
                                      'shortcut-action-${entry.key}',
                                    ),
                                    autofocus: entry.key == '__none',
                                    title: entry.value,
                                    selected:
                                        (store.shortcuts[key] ?? '__none') ==
                                        entry.key,
                                    onPressed: () =>
                                        Navigator.pop(pickerContext, entry.key),
                                  ),
                              ],
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(pickerContext),
                              child: const Text('Back'),
                            ),
                          ],
                        ),
                      );
                      if (action == null || !mounted) return;
                      try {
                        await store.setShortcut(
                          key,
                          action == '__none' ? null : action,
                        );
                      } catch (_) {
                        if (mounted)
                          _message(
                            'Could not save shortcut. Please try again.',
                          );
                      }
                    },
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Back'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _artworkSettings(LauncherAppItem app) async {
    final store = _customization;
    if (store == null) return;
    final pack = tvIconPackArtwork(app.id, app.name);
    final automatic = pack == null
        ? installedAppArtwork(app)
        : Future<ImageProvider?>.value(pack);
    bool busy = false;
    String? error;
    await showLumaDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (_, update) {
          Future<void> save(String? source, {Uint8List? bytes}) async {
            if (busy) return;
            update(() {
              busy = true;
              error = null;
            });
            try {
              await store.setArtwork(app.id, source, bytes: bytes);
            } catch (_) {
              if (dialogContext.mounted)
                update(
                  () => error =
                      'Could not save artwork. Choose a valid image under 8 MB.',
                );
            } finally {
              if (dialogContext.mounted) update(() => busy = false);
            }
          }

          return LumaMenuDialog(
            title: Text('${app.name} artwork'),
            content: FocusHighlightLayer(
              menu: true,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(
                    child: SizedBox(
                      width: 192,
                      height: 108,
                      child: AppArtworkBuilder(
                        id: app.id,
                        future: automatic,
                        original: () => installedAppArtwork(app),
                        builder: (_, snapshot) => snapshot.data == null
                            ? Center(child: Text(app.name))
                            : ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image(
                                  image: snapshot.data!,
                                  fit: BoxFit.contain,
                                ),
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (error != null) Text(error!),
                  if (busy) const LinearProgressIndicator(),
                  TvMenuRow(
                    key: const ValueKey('artwork-automatic'),
                    autofocus: true,
                    title: 'Automatic',
                    selected: store.artwork[app.id] == null,
                    onPressed: () => save(null),
                  ),
                  TvMenuRow(
                    key: const ValueKey('artwork-original'),
                    title: 'Installed app artwork',
                    selected: store.artwork[app.id] == 'original',
                    onPressed: () => save('original'),
                  ),
                  if (widget.onPickAppArtwork != null)
                    TvMenuRow(
                      key: const ValueKey('artwork-custom'),
                      title: 'Choose image',
                      icon: Icons.photo_library_outlined,
                      selected: store.artwork[app.id] == 'custom',
                      onPressed: () async {
                        if (busy) return;
                        update(() {
                          busy = true;
                          error = null;
                        });
                        Uint8List? bytes;
                        try {
                          bytes = await widget.onPickAppArtwork!();
                        } catch (_) {
                          if (dialogContext.mounted)
                            update(() => error = 'Could not open this image.');
                        }
                        if (!dialogContext.mounted) return;
                        update(() => busy = false);
                        if (bytes != null) await save('custom', bytes: bytes);
                      },
                    ),
                  TvMenuRow(
                    key: const ValueKey('artwork-pack'),
                    title: 'Choose a TV card',
                    icon: Icons.grid_view_rounded,
                    onPressed: () async {
                      if (busy) return;
                      final icons = tvIconPackNames.values.toSet().toList()
                        ..sort();
                      final source = await showLumaDialog<String>(
                        context: dialogContext,
                        builder: (pickerContext) => LumaMenuDialog(
                          title: const Text('TV cards'),
                          content: FocusHighlightLayer(
                            menu: true,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                for (final icon in icons)
                                  TvMenuRow(
                                    key: ValueKey('artwork-pack-$icon'),
                                    autofocus: icon == icons.first,
                                    title: icon.replaceAll('-', ' '),
                                    trailing: Image.asset(
                                      'assets/tv-icons/$icon.png',
                                      cacheWidth: 144,
                                      cacheHeight: 84,
                                      width: 72,
                                      height: 42,
                                      fit: BoxFit.contain,
                                    ),
                                    selected:
                                        store.artwork[app.id] == 'pack:$icon',
                                    onPressed: () => Navigator.pop(
                                      pickerContext,
                                      'pack:$icon',
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(pickerContext),
                              child: const Text('Back'),
                            ),
                          ],
                        ),
                      );
                      if (source != null && dialogContext.mounted)
                        await save(source);
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: busy ? null : () => Navigator.pop(dialogContext),
                child: const Text('Back'),
              ),
            ],
          );
        },
      ),
    );
  }
}
