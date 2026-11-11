part of 'launcher_home.dart';

extension _HomePersonalization on _LauncherHomeState {
  FocusNode _nodeFor(String id, bool library) => _rememberedFocus.putIfAbsent(
    '${library ? 'library' : 'home'}:$id',
    () => FocusNode(debugLabel: 'Remember $id'),
  );

  Future<void> _loadHomePreferences() async {
    try {
      final preferences = HomePreferences(
        await SharedPreferences.getInstance(),
      );
      if (!mounted) return;
      _updateHome(() => _homePreferences = preferences);
      unawaited(_extractAccent());
    } catch (_) {
      // The launcher remains usable if local storage is unavailable.
      if (mounted) _updateHome(() => _selectionRestored = true);
    }
  }

  Future<void> _saveSelection() async {
    final app = _focusedApp;
    if (!_selectionRestored || app == null) return;
    try {
      await _homePreferences?.saveSelection(
        app.id,
        _selectionLibrary,
        _minimalScroll.hasClients ? _minimalScroll.offset : 0,
      );
    } catch (_) {
      /* A storage error must not prevent launching an app. */
    }
  }

  void _scheduleSelectionRestore() {
    final prefs = _homePreferences;
    if (_selectionRestored ||
        _restoreScheduled ||
        !widget.autofocusApps ||
        prefs == null ||
        widget.loading ||
        widget.apps.isEmpty)
      return;
    _restoreScheduled = true;
    // Snapshot before automatic focus can overwrite the previous session.
    final id = prefs.remember ? prefs.selected : null;
    final library = prefs.library;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final app = widget.apps.where((a) => a.id == id).firstOrNull;
      if (app != null && library) {
        _selectionRestored = true;
        unawaited(_minimalLibrary(initialApp: app.id));
        return;
      }
      if (app != null) {
        final index = widget.favorites.toList().indexWhere(
          (a) => a.id == app.id,
        );
        if (index >= 0) {
          (index == 0
                  ? _firstAppFocus
                  : index == widget.favorites.length - 1
                  ? _lastDockFocus
                  : _nodeFor(app.id, false))
              .requestFocus();
        }
      }
      _selectionRestored = true;
    });
  }

  Future<void> _extractAccent() async {
    _cancelAccent?.call();
    final ticket = ++_accentTicket;
    // Always sample: the wallpaper tone keeps glass legible on bright photos
    // even when the optional accent colour is switched off.
    final wantAccent = _homePreferences?.accent ?? false;
    final stream = ResizeImage(
      widget.wallpaper,
      width: 32,
      height: 32,
      policy: ResizeImagePolicy.fit,
    ).resolve(const ImageConfiguration());
    final ready = Completer<ImageInfo?>();
    late ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        if (!ready.isCompleted) ready.complete(info.clone());
      },
      onError: (Object error, StackTrace? stack) {
        if (!ready.isCompleted) ready.complete(null);
      },
    );
    final timeout = Timer(const Duration(seconds: 5), () {
      if (!ready.isCompleted) ready.complete(null);
    });
    _cancelAccent = () {
      timeout.cancel();
      stream.removeListener(listener);
      if (!ready.isCompleted) ready.complete(null);
    };
    stream.addListener(listener);
    ImageInfo? info;
    ui.Image? thumbnail;
    try {
      info = await ready.future;
      if (info == null || !mounted || ticket != _accentTicket) return;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawImageRect(
        info.image,
        Rect.fromLTWH(
          0,
          0,
          info.image.width.toDouble(),
          info.image.height.toDouble(),
        ),
        const Rect.fromLTWH(0, 0, 16, 16),
        Paint(),
      );
      final picture = recorder.endRecording();
      thumbnail = await picture.toImage(16, 16);
      picture.dispose();
      final bytes = await thumbnail.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      if (bytes == null || !mounted || ticket != _accentTicket) return;
      // 16 rows: 0-3 sit behind the top bar and quick settings, 10-14 behind
      // the favourites dock.
      (int, int, int, int) pixel(int x, int y) {
        final i = (y * 16 + x) * 4;
        return (
          bytes.getUint8(i),
          bytes.getUint8(i + 1),
          bytes.getUint8(i + 2),
          bytes.getUint8(i + 3),
        );
      }

      WallpaperTone.notifier.value = WallpaperTone(
        top: bandLightness(pixel, 16, 0, 4),
        bottom: bandLightness(pixel, 16, 10, 15),
      );
      if (!wantAccent) return;
      double r = 0, g = 0, b = 0, count = 0;
      for (var i = 0; i < bytes.lengthInBytes; i += 4) {
        if (bytes.getUint8(i + 3) < 128) continue;
        r += bytes.getUint8(i);
        g += bytes.getUint8(i + 1);
        b += bytes.getUint8(i + 2);
        count++;
      }
      if (count == 0) return;
      final sampled = HSLColor.fromColor(
        Color.fromARGB(
          255,
          (r / count).round(),
          (g / count).round(),
          (b / count).round(),
        ),
      );
      // Pastel focus remains readable; original brand artwork is untouched.
      _updateHome(
        () => _wallpaperAccent = sampled
            .withSaturation(.28)
            .withLightness(.82)
            .toColor(),
      );
    } catch (_) {
      // Neutral focus is the fallback for missing or undecodable wallpaper.
    } finally {
      timeout.cancel();
      stream.removeListener(listener);
      if (ticket == _accentTicket) _cancelAccent = null;
      info?.dispose();
      thumbnail?.dispose();
    }
  }

  Future<void> _openHomeContent() => _navigateHomeRows(null, 1);

  List<String> get _visibleHomeRows => [
    for (final row in _homePreferences?.order ?? const <String>[])
      if (row == 'watch' &&
          _homePreferences!.visible(row) &&
          widget.homeHasWatchContent &&
          (widget.homeContinueWatching ?? widget.continueWatching) != null)
        row,
  ];

  Future<void> _navigateHomeRows(String? current, int direction) async {
    final rows = _visibleHomeRows;
    final index = current == null
        ? (direction > 0 ? -1 : rows.length)
        : rows.indexOf(current);
    final next = index + direction;
    if (next < 0) {
      await _goHome();
      return;
    }
    // Nothing below the last home row: the screen stays clean.
    if (next >= rows.length) return;
    final ticket = ++_homeTicket;
    final id = rows[next];
    final readyFocus = _homeRowTarget(id);
    if (readyFocus?.context != null) {
      // Hand off the remote immediately. The focused card/controls reveal
      // themselves; subsequent arrows must act on the new section.
      readyFocus!.requestFocus();
      return;
    }
    final duration = motionReduced(context, widget.reducedMotion)
        ? Duration.zero
        : lumaScrollDuration;
    var target = _homeRowAnchors[id]?.currentContext;
    target ??= _homeContentAnchor.currentContext;
    if (target != null)
      await Scrollable.ensureVisible(
        target,
        duration: duration,
        alignment: .18,
        curve: Curves.easeOutCubic,
      );
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || ticket != _homeTicket) return;
    target = _homeRowAnchors[id]?.currentContext;
    if (target != null)
      await Scrollable.ensureVisible(
        target,
        duration: duration,
        alignment: .18,
        curve: Curves.easeOutCubic,
      );
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || ticket != _homeTicket) return;
    _homeRowTarget(id)?.requestFocus();
  }

  FocusNode? _homeRowTarget(String id) {
    final candidates =
        _homeRowScopes[id]?.traversalDescendants
            .where(
              (node) =>
                  node.canRequestFocus &&
                  node is! FocusScopeNode &&
                  !node.descendants.any(
                    (child) =>
                        child.canRequestFocus && child is! FocusScopeNode,
                  ),
            )
            .toList() ??
        <FocusNode>[];
    return candidates
            .where(
              (node) =>
                  node.context
                      ?.findAncestorWidgetOfExactType<ProgrammeCard>() !=
                  null,
            )
            .firstOrNull ??
        candidates.firstOrNull;
  }

  Widget _homeRow(String id, Widget child) => FocusScope(
    key: _homeRowAnchors.putIfAbsent(id, GlobalKey.new),
    node: _homeRowScopes.putIfAbsent(
      id,
      () => FocusScopeNode(debugLabel: 'Home row $id'),
    ),
    onKeyEvent: (_, event) {
      final direction = event.logicalKey == LogicalKeyboardKey.arrowDown
          ? 1
          : event.logicalKey == LogicalKeyboardKey.arrowUp
          ? -1
          : 0;
      if (direction == 0) return KeyEventResult.ignored;
      if (event is KeyDownEvent || event is KeyRepeatEvent)
        unawaited(_navigateHomeRows(id, direction));
      return KeyEventResult.handled;
    },
    child: child,
  );

  bool get _hasHomeContent =>
      _homePreferences != null &&
      ((_homePreferences!.visible('watch') &&
          widget.homeHasWatchContent &&
          (widget.homeContinueWatching ?? widget.continueWatching) != null));

  List<Widget> _optionalHomeRows(double width) {
    final prefs = _homePreferences;
    if (prefs == null) return const [];
    return [
      for (final row in prefs.order)
        if (row == 'watch' && prefs.visible(row))
          if (row == 'watch' &&
              widget.homeHasWatchContent &&
              (widget.homeContinueWatching ?? widget.continueWatching) != null)
            _homeRow(
              'watch',
              Padding(
                key: const ValueKey('home-watch-row'),
                padding: const EdgeInsets.symmetric(
                  horizontal: 48,
                  vertical: 12,
                ),
                child: widget.homeContinueWatching ?? widget.continueWatching!,
              ),
            ),
    ];
  }

  Future<void> _homeLayoutSettings() async {
    if (_homePreferences == null) await _loadHomePreferences();
    if (!mounted || _homePreferences == null) return;
    final prefs = _homePreferences!;
    await showLumaDialog<void>(
      context: context,
      barrierDismissible: false,
      reducedMotion: widget.reducedMotion,
      builder: (_) => StatefulBuilder(
        builder: (context, update) {
          Future<void> change(Future<bool> write) async {
            await write;
            if (!mounted || !context.mounted) return;
            _updateHome(() {});
            _settingsRevision.value++;
            update(() {});
          }

          return WallpaperAccentScope(
            color: prefs.accent ? _wallpaperAccent : null,
            child: LumaMenuDialog(
              title: const Text('Home layout'),
              content: FocusHighlightLayer(
                menu: true,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Favourites stay first. All apps opens on its own page.',
                    ),
                    const SizedBox(height: 12),
                    for (final size in HomePreferences.sizes)
                      TvMenuRow(
                        key: ValueKey('home-size-$size'),
                        title:
                            '${size[0].toUpperCase()}${size.substring(1)} cards',
                        selected: prefs.size == size,
                        autofocus: prefs.size == size,
                        icon: Icons.crop_landscape,
                        onPressed: () => change(
                          prefs.storage.setString('home_card_size', size),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: SizedBox(
                        key: const ValueKey('home-card-preview'),
                        width: prefs.size == 'small'
                            ? 100
                            : prefs.size == 'large'
                            ? 180
                            : 140,
                        child: AspectRatio(
                          aspectRatio: 16 / 9,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: MinimalPalette.of(context).background,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: MinimalPalette.of(context).accent,
                              ),
                            ),
                            child: const Center(child: Text('App preview')),
                          ),
                        ),
                      ),
                    ),
                    TvMenuRow(
                      key: const ValueKey('home-remember'),
                      title: 'Remember selection',
                      selected: prefs.remember,
                      subtitle: prefs.remember
                          ? 'On · restore after restart'
                          : 'Off',
                      icon: Icons.restore,
                      onPressed: () => change(
                        prefs.storage.setBool(
                          'home_remember_selection',
                          !prefs.remember,
                        ),
                      ),
                    ),
                    TvMenuRow(
                      key: const ValueKey('home-accent'),
                      title: 'Wallpaper accent',
                      selected: prefs.accent,
                      subtitle: prefs.accent
                          ? 'On · subtle focus colour'
                          : 'Off · neutral focus',
                      icon: Icons.palette_outlined,
                      onPressed: () async {
                        await change(
                          prefs.storage.setBool(
                            'home_wallpaper_accent',
                            !prefs.accent,
                          ),
                        );
                        if (prefs.accent) unawaited(_extractAccent());
                      },
                    ),
                    const SizedBox(height: 8),
                    if (widget.onLayout != null)
                      TvMenuRow(
                        title: 'App collections & grid',
                        icon: Icons.folder_outlined,
                        onPressed: widget.onLayout!,
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Back'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
