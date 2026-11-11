part of 'launcher_home.dart';

extension _MinimalHomeView on _LauncherHomeState {
  Future<void> _minimalLibrary({String? initialApp}) async {
    await Navigator.of(context).push<void>(
      PageRouteBuilder(
        settings: const RouteSettings(name: '/all-apps'),
        transitionDuration: motionReduced(context, widget.reducedMotion)
            ? Duration.zero
            : const Duration(milliseconds: 140),
        reverseTransitionDuration: motionReduced(context, widget.reducedMotion)
            ? Duration.zero
            : const Duration(milliseconds: 140),
        pageBuilder: (_, animation, secondary) => ValueListenableBuilder<int>(
          valueListenable: _settingsRevision,
          builder: (_, revision, child) => _LumaAppsPage(
            apps: widget.apps,
            favorites: widget.favorites,
            wallpaper: widget.wallpaper,
            wallpaperCache: _appsWallpaperCache,
            wallpaperRevision: widget.wallpaperRevision,
            sections: widget.sections,
            columns: widget.gridColumns,
            reducedMotion: widget.reducedMotion,
            onLaunch: _launch,
            onOptions: _options,
            onManage: widget.onManage,
            initialApp: initialApp ?? _lastAppsSelection,
            onFocused: (app) {
              _lastAppsSelection = app.id;
              _trackApp(app);
              _selectionLibrary = true;
              unawaited(_saveSelection());
            },
          ),
        ),
        transitionsBuilder: (_, animation, secondary, child) =>
            MenuSlideTransition(
              animation: animation,
              begin: const Offset(0, 18),
              child: child,
            ),
      ),
    );
    if (mounted)
      (widget.favorites.isEmpty ? _addDockFocus : _firstAppFocus)
          .requestFocus();
  }

  Future<void> _minimalPlayNext() async {
    if (!widget.showWatchNext) widget.onWatchNextChanged?.call(true);
    await showLumaDialog<void>(
      context: context,
      reducedMotion: widget.reducedMotion,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(32),
        child: GlassSurface(
          mode: LauncherMaterial.minimal,
          sheet: true,
          child: SizedBox(
            width: 900,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.play_circle_outline_rounded,
                        color: MinimalPalette.of(context).text,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Play next',
                          style: TextStyle(
                            fontSize: 22,
                            color: MinimalPalette.of(context).text,
                          ),
                        ),
                      ),
                      TextButton(
                        autofocus: true,
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Back'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Flexible(
                    child: SingleChildScrollView(
                      child:
                          widget.continueWatching ??
                          Text(
                            widget.preview
                                ? 'Continue watching is available on your TV for apps that share their progress.'
                                : 'No continue-watching content is available.',
                            style: TextStyle(
                              color: MinimalPalette.of(context).muted,
                            ),
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _minimalView(BuildContext context) {
    _minimalScroll.reducedMotion = motionReduced(context, widget.reducedMotion);
    final glassTheme = [
      'glass',
      'glass-real',
    ].contains(widget.minimalBackground);
    final favorites = widget.favorites.toList();
    final size = MediaQuery.sizeOf(context);
    final clockExtent = widget.clockStyle == 'analog'
        ? clockAnalogExtent(widget.clockSize)
        : MediaQuery.textScalerOf(
                context,
              ).scale(clockDigitalExtent(widget.clockSize)) *
              1.2;
    final headerHeight = (clockExtent + 40).clamp(84.0, double.infinity);
    final homeGutter = (size.width * .025).clamp(20.0, 48.0);
    final dockPadding = (size.width * .008).clamp(8.0, 12.0);
    final dockGap = (size.width * .015).clamp(14.0, 24.0);
    _scheduleSelectionRestore();
    final cardSize = _homePreferences?.size ?? 'medium';
    final slots = cardSize == 'large'
        ? 4.0
        : cardSize == 'small'
        ? 7.0
        : 6.0;
    final width =
        ((size.width -
                    homeGutter * 2 -
                    dockPadding * 2 -
                    24 -
                    dockGap * (slots - 1)) /
                slots)
            .clamp(80.0, 300.0);
    final dockRailHeight =
        (width - 8) * 9 / 16 +
        20 +
        10 +
        (MediaQuery.textScalerOf(context).scale(12) * 1.3).ceilToDouble() +
        14;
    Widget tile(
      LauncherAppItem app, {
      Key? key,
      FocusNode? focus,
      bool autofocus = false,
      bool homeRail = false,
      VoidCallback? down,
      VoidCallback? up,
      VoidCallback? right,
      VoidCallback? left,
    }) => _MinimalAppTile(
      key: key,
      app: app,
      focusNode: homeRail && _dockMoveId == app.id
          ? _dockMoveFocus
          : focus ?? _nodeFor(app.id, !homeRail),
      moving: homeRail && _dockMoveId == app.id,
      onMove: (offset) => unawaited(_moveDockApp(offset)),
      onFinishMove: _finishDockMove,
      autofocus: autofocus,
      horizontalOnly: homeRail,
      compactGlass: homeRail,
      tvStyle: homeRail,
      focusOnlyLabel: homeRail,
      reducedMotion: widget.reducedMotion,
      onPressed: () => _dockMoveId == app.id ? _finishDockMove() : _launch(app),
      onOptions: () =>
          _dockMoveId == app.id ? _finishDockMove() : _options(app),
      onFocused: () {
        _trackApp(app);
        _selectionLibrary = !homeRail;
        if (_selectionRestored) {
          _selectionSave?.cancel();
          _selectionSave = Timer(
            const Duration(milliseconds: 450),
            () => unawaited(_saveSelection()),
          );
        }
      },
      onDown: down,
      onUp: up,
      onRight: right,
      onLeft: left,
    );
    return WallpaperAccentScope(
      color: (_homePreferences?.accent ?? true) ? _wallpaperAccent : null,
      child: Builder(
        builder: (context) => PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop && (ModalRoute.of(context)?.isCurrent ?? true))
              _goHome();
          },
          child: Scaffold(
            key: const ValueKey('minimal-home'),
            backgroundColor: glassTheme
                ? MinimalPalette(widget.minimalBackground).background
                : SolidThemeScope.of(context),
            body: PreparedBackdropScope(
              image: glassTheme ? _homeEdgeImage : null,
              origin: _homeBackdropOrigin,
              fallback: glassTheme
                  ? MinimalPalette(widget.minimalBackground).background
                  : SolidThemeScope.of(context),
              child: CinematicBackdropHost(
                child: Stack(
                  key: _homeBackdropOrigin,
                  children: [
                    if (widget.minimalBackground == 'wallpaper' || glassTheme)
                      Positioned.fill(
                        child: CinematicWallpaper(
                          child: RepaintBoundary(
                            key: const ValueKey('home-wallpaper'),
                            child: glassTheme
                                ? GlassWallpaper(
                                    key: ValueKey(
                                      'home-wallpaper-${widget.wallpaperRevision}',
                                    ),
                                    image: widget.wallpaper,
                                    scroll: _minimalScroll,
                                    onDimPrepared: _preparedHomeEdges,
                                  )
                                : Image(
                                    key: ValueKey(
                                      'home-wallpaper-${widget.wallpaperRevision}',
                                    ),
                                    // Decode at screen width, not source width:
                                    // the default 2560x1707 asset is ~17 MB as a
                                    // full-size texture vs ~8 MB at 1080p.
                                    image: ResizeImage.resizeIfNeeded(
                                      (MediaQuery.sizeOf(context).width *
                                              MediaQuery.devicePixelRatioOf(
                                                context,
                                              ))
                                          .round(),
                                      null,
                                      widget.wallpaper,
                                    ),
                                    gaplessPlayback: true,
                                    fit: BoxFit.cover,
                                    color: glassTheme
                                        ? const Color(0x10000000)
                                        : const Color(0x99000000),
                                    colorBlendMode: BlendMode.darken,
                                  ),
                          ),
                        ),
                      ),
                    if (glassTheme && widget.depthAsset != null)
                      Positioned.fill(
                        child: DepthClock(
                          key: ValueKey('depth-clock-${widget.depthAsset}'),
                          wallpaper: widget.depthAsset!,
                          image: widget.wallpaper,
                          pattern: widget.timeFormat,
                          scroll: _minimalScroll,
                        ),
                      ),
                    const Positioned.fill(child: CinematicBackdropLayer()),
                    if (_dockMoveId != null)
                      Positioned(
                        top: 88,
                        left: 160,
                        right: 160,
                        child: IgnorePointer(
                          child: Material(
                            key: const ValueKey('dock-move-hint'),
                            color: const Color(0xe6202630),
                            borderRadius: BorderRadius.circular(14),
                            child: const Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              child: Text(
                                'Hold ◀ / ▶ to move · OK or Back to finish\nEach move saves automatically',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 13),
                              ),
                            ),
                          ),
                        ),
                      ),
                    FocusTraversalGroup(
                      policy: ReadingOrderTraversalPolicy(),
                      child: FocusHighlightLayer(
                        cardFocus: true,
                        frameAbove: glassTheme,
                        reducedMotion: widget.reducedMotion,
                        child: CustomScrollView(
                          key: const ValueKey('minimal-scroll'),
                          controller: _minimalScroll,
                          slivers: [
                            SliverPersistentHeader(
                              pinned: false,
                              delegate: _MinimalHeaderDelegate(
                                extent: headerHeight,
                                child: Align(
                                  alignment: Alignment.topCenter,
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      48,
                                      16,
                                      24,
                                      12,
                                    ),
                                    child: RepaintBoundary(
                                      key: const ValueKey('home-action-pills'),
                                      child: Focus(
                                        canRequestFocus: false,
                                        skipTraversal: true,
                                        onKeyEvent: (row, event) {
                                          if (event.logicalKey ==
                                              LogicalKeyboardKey.arrowDown) {
                                            if (event is KeyDownEvent)
                                              _goHome();
                                            return KeyEventResult.handled;
                                          }
                                          if (event.logicalKey ==
                                              LogicalKeyboardKey.arrowUp)
                                            return KeyEventResult.handled;
                                          if (event.logicalKey ==
                                                  LogicalKeyboardKey
                                                      .arrowLeft &&
                                              _searchFocus.hasFocus)
                                            return KeyEventResult.handled;
                                          return RemoteFocusRow.handle(
                                            row,
                                            event,
                                          );
                                        },
                                        child: Row(
                                          mainAxisSize: MainAxisSize.max,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            _HomePillButton(
                                              glass: glassTheme,
                                              tooltip: 'Search apps',
                                              focusNode: _searchFocus,
                                              onPressed: () => _search(),
                                              child: const Icon(
                                                Icons.search_rounded,
                                                size: 22,
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            _HomePillButton(
                                              glass: glassTheme,
                                              tooltip: 'Voice search',
                                              onPressed: _voice,
                                              child: const Icon(
                                                Icons.mic_none_rounded,
                                                size: 22,
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            _HomePillButton(
                                              buttonKey: const ValueKey(
                                                'open-all-apps',
                                              ),
                                              glass: glassTheme,
                                              tooltip: 'All apps',
                                              onPressed: _minimalLibrary,
                                              child: const Icon(
                                                Icons.apps_rounded,
                                                size: 22,
                                              ),
                                            ),
                                            const Spacer(),
                                            // The bell appears only when
                                            // there is something new; the
                                            // clock menu always has the way
                                            // in.
                                            if (widget.onNotifications !=
                                                    null &&
                                                widget.notificationCount >
                                                    0) ...[
                                              _HomePillButton(
                                                buttonKey: const ValueKey(
                                                  'home-notifications',
                                                ),
                                                glass: glassTheme,
                                                tooltip: 'Notifications',
                                                onPressed:
                                                    widget.onNotifications!,
                                                child: _NotificationBell(
                                                  count:
                                                      widget.notificationCount,
                                                ),
                                              ),
                                              const SizedBox(width: 10),
                                            ],
                                            _HomePillButton(
                                              buttonKey: const ValueKey(
                                                'home-clock-pill',
                                              ),
                                              glass: glassTheme,
                                              tooltip: 'Clock',
                                              bare:
                                                  widget.clockStyle == 'analog',
                                              onPressed: _controls,
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  SizedBox(
                                                    height:
                                                        widget.clockStyle ==
                                                            'analog'
                                                        ? clockAnalogExtent(
                                                            widget.clockSize,
                                                          )
                                                        : 14 +
                                                              10 *
                                                                  clockSizePosition(
                                                                    widget
                                                                        .clockSize,
                                                                  ) /
                                                                  100,
                                                    child: FittedBox(
                                                      child: LumaClock(
                                                        style:
                                                            widget.clockStyle,
                                                        size: widget.clockSize,
                                                        pattern:
                                                            widget.timeFormat,
                                                      ),
                                                    ),
                                                  ),
                                                  if (widget.clockStyle !=
                                                      'analog') ...[
                                                    const SizedBox(width: 10),
                                                    const Icon(
                                                      Icons.wifi_rounded,
                                                      size: 14,
                                                    ),
                                                    const SizedBox(width: 8),
                                                    const Icon(
                                                      Icons.tune_rounded,
                                                      size: 14,
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            SliverToBoxAdapter(
                              child: SizedBox(
                                height: (size.height - headerHeight).clamp(
                                  dockRailHeight + dockPadding * 2 + 60,
                                  double.infinity,
                                ),
                                child: Padding(
                                  padding: EdgeInsets.fromLTRB(
                                    homeGutter,
                                    0,
                                    homeGutter,
                                    32,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Spacer(flex: 3),
                                      _DockScrollFade(
                                        controller: _minimalScroll,
                                        child: LiquidGlassV2(
                                          key: const ValueKey(
                                            'home-favourites-dock',
                                          ),
                                          enabled: glassTheme,
                                          blurBuilder: widget.blurBuilder,
                                          band: WallpaperBand.bottom,
                                          glassInset: EdgeInsets.only(
                                            // Artwork starts after the scroll inset
                                            // and its centred focus slot. Match the
                                            // glass margins around the artwork,
                                            // excluding the label beneath it.
                                            top: 14,
                                            bottom:
                                                30 +
                                                (MediaQuery.textScalerOf(
                                                          context,
                                                        ).scale(12) *
                                                        1.3)
                                                    .ceilToDouble(),
                                          ),
                                          padding: EdgeInsets.all(dockPadding),
                                          child: SizedBox(
                                            height: dockRailHeight,
                                            // The reference dock has crisp clipped edges.
                                            // Avoid a row-sized offscreen shader mask.
                                            child: Padding(
                                              padding: EdgeInsets.zero,
                                              child: SingleChildScrollView(
                                                scrollDirection:
                                                    Axis.horizontal,
                                                key: const PageStorageKey(
                                                  'minimal-favourites-rail',
                                                ),
                                                // Keep the complete rounded card inside the
                                                // viewport while its focus lift animates.
                                                padding: EdgeInsets.fromLTRB(
                                                  12,
                                                  4,
                                                  12,
                                                  4,
                                                ),
                                                child: Row(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    for (
                                                      var i = 0;
                                                      i < favorites.length;
                                                      i++
                                                    ) ...[
                                                      SizedBox(
                                                        key: ValueKey(
                                                          'dock-position-${favorites[i].id}',
                                                        ),
                                                        width: width,
                                                        child: tile(
                                                          favorites[i],
                                                          homeRail: true,
                                                          key: ValueKey(
                                                            'favorite-${favorites[i].id}',
                                                          ),
                                                          focus: i == 0
                                                              ? _firstAppFocus
                                                              : i ==
                                                                    favorites
                                                                            .length -
                                                                        1
                                                              ? _lastDockFocus
                                                              : null,
                                                          autofocus:
                                                              widget
                                                                  .autofocusApps &&
                                                              i == 0,
                                                          down:
                                                              widget
                                                                  .apps
                                                                  .isEmpty
                                                              ? null
                                                              : _openHomeContent,
                                                          up: _searchFocus
                                                              .requestFocus,
                                                          left: () {
                                                            if (i > 0) {
                                                              (i == 1
                                                                      ? _firstAppFocus
                                                                      : _nodeFor(
                                                                          favorites[i - 1]
                                                                              .id,
                                                                          false,
                                                                        ))
                                                                  .requestFocus();
                                                            }
                                                          },
                                                          right:
                                                              i ==
                                                                  favorites
                                                                          .length -
                                                                      1
                                                              ? _addDockFocus
                                                                    .requestFocus
                                                              : () {
                                                                  (i + 1 ==
                                                                              favorites.length -
                                                                                  1
                                                                          ? _lastDockFocus
                                                                          : _nodeFor(
                                                                              favorites[i +
                                                                                      1]
                                                                                  .id,
                                                                              false,
                                                                            ))
                                                                      .requestFocus();
                                                                },
                                                        ),
                                                      ),
                                                      SizedBox(width: dockGap),
                                                    ],
                                                    SizedBox(
                                                      key: _minimalAddAnchor,
                                                      width: 48,
                                                      child: Focus(
                                                        canRequestFocus: false,
                                                        skipTraversal: true,
                                                        onFocusChange: (focused) {
                                                          if (focused)
                                                            WidgetsBinding.instance.addPostFrameCallback((
                                                              _,
                                                            ) {
                                                              final target =
                                                                  _minimalAddAnchor
                                                                      .currentContext;
                                                              if (mounted &&
                                                                  target !=
                                                                      null &&
                                                                  _addDockFocus
                                                                      .hasFocus)
                                                                Scrollable.maybeOf(
                                                                  target,
                                                                  axis: Axis
                                                                      .horizontal,
                                                                )?.position.ensureVisible(
                                                                  target
                                                                      .findRenderObject()!,
                                                                  duration:
                                                                      motionReduced(
                                                                        context,
                                                                        widget
                                                                            .reducedMotion,
                                                                      )
                                                                      ? Duration
                                                                            .zero
                                                                      : const Duration(
                                                                          milliseconds:
                                                                              180,
                                                                        ),
                                                                  curve: Curves
                                                                      .easeOutCubic,
                                                                  alignmentPolicy:
                                                                      ScrollPositionAlignmentPolicy
                                                                          .keepVisibleAtEnd,
                                                                );
                                                            });
                                                        },
                                                        onKeyEvent: (_, event) {
                                                          if (event
                                                                  .logicalKey ==
                                                              LogicalKeyboardKey
                                                                  .arrowUp) {
                                                            if (event
                                                                is KeyDownEvent)
                                                              _searchFocus
                                                                  .requestFocus();
                                                            return KeyEventResult
                                                                .handled;
                                                          }
                                                          if (event
                                                                  .logicalKey ==
                                                              LogicalKeyboardKey
                                                                  .arrowRight)
                                                            return KeyEventResult
                                                                .handled;
                                                          if (event
                                                              is! KeyDownEvent)
                                                            return KeyEventResult
                                                                .ignored;
                                                          if (event.logicalKey ==
                                                                  LogicalKeyboardKey
                                                                      .arrowLeft &&
                                                              favorites
                                                                  .isNotEmpty) {
                                                            (favorites.length ==
                                                                        1
                                                                    ? _firstAppFocus
                                                                    : _lastDockFocus)
                                                                .requestFocus();
                                                            return KeyEventResult
                                                                .handled;
                                                          }
                                                          if (event.logicalKey ==
                                                                  LogicalKeyboardKey
                                                                      .arrowDown &&
                                                              widget
                                                                  .apps
                                                                  .isNotEmpty) {
                                                            _openHomeContent();
                                                            return KeyEventResult
                                                                .handled;
                                                          }
                                                          return KeyEventResult
                                                              .ignored;
                                                        },
                                                        child: SizedBox(
                                                          height:
                                                              (width - 8) *
                                                                  9 /
                                                                  16 +
                                                              20,
                                                          child: Align(
                                                            alignment: Alignment
                                                                .center,
                                                            child: SizedBox(
                                                              height:
                                                                  (width - 8) *
                                                                  9 /
                                                                  16,
                                                              child: Center(
                                                                child: SizedBox.square(
                                                                  dimension: 44,
                                                                  child: _MinimalControl(
                                                                    focusNode:
                                                                        _addDockFocus,
                                                                    autofocus:
                                                                        widget
                                                                            .autofocusApps &&
                                                                        favorites
                                                                            .isEmpty,
                                                                    tooltip:
                                                                        'Add dock apps',
                                                                    icon: Icons
                                                                        .add_rounded,
                                                                    onPressed:
                                                                        _chooseDockApps,
                                                                  ),
                                                                ),
                                                              ),
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
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            SliverToBoxAdapter(
                              child: FocusScope(
                                key: _homeContentAnchor,
                                node: _homeContentFocus,
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: _optionalHomeRows(width),
                                ),
                              ),
                            ),
                            SliverToBoxAdapter(
                              // Room for the last row to scroll up to the
                              // middle of the screen now nothing sits below it.
                              child: SizedBox(height: size.height * .4),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LumaAppsPage extends StatefulWidget {
  const _LumaAppsPage({
    required this.apps,
    required this.favorites,
    required this.wallpaper,
    required this.wallpaperCache,
    required this.wallpaperRevision,
    required this.sections,
    required this.columns,
    required this.reducedMotion,
    required this.onLaunch,
    required this.onOptions,
    required this.onManage,
    required this.onFocused,
    this.initialApp,
  });
  final List<LauncherAppItem> apps, favorites;
  final ImageProvider wallpaper;
  final SharedBlurCache wallpaperCache;
  final int wallpaperRevision;
  final List<LauncherAppSection> sections;
  final int columns;
  final bool reducedMotion;
  final Future<void> Function(LauncherAppItem) onLaunch;
  final void Function(LauncherAppItem) onOptions;
  final VoidCallback onManage;
  final String? initialApp;
  final ValueChanged<LauncherAppItem> onFocused;
  @override
  State<_LumaAppsPage> createState() => _LumaAppsPageState();
}

class _LumaAppsPageState extends State<_LumaAppsPage> {
  String? category, selected;
  String sortOrder = 'default';
  final sortFocus = FocusNode(debugLabel: 'All apps sort');
  ScrollController? scroll;
  final backFocus = FocusNode(debugLabel: 'All apps back');
  final filterNodes = {
    for (final filter in tvAppFilters)
      filter: FocusNode(debugLabel: 'All apps filter ${tvFilterLabel(filter)}'),
  };
  final nodes = <String, FocusNode>{};
  double rowExtent = 120, dockExtent = 0;
  late int columns;
  bool focusContent = true;
  List<LauncherAppItem> get visibleApps {
    final result =
        (category == null
                ? widget.apps
                : widget.apps.where((app) => categoryFor(app) == category))
            .toList();
    if (sortOrder == 'az')
      result.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
    if (sortOrder == 'newest')
      result.sort((a, b) {
        final time = b.installedAt.compareTo(a.installedAt);
        return time == 0
            ? a.name.toLowerCase().compareTo(b.name.toLowerCase())
            : time;
      });
    return result;
  }

  Future<void> chooseSort() async {
    await showLumaDialog<void>(
      context: context,
      builder: (dialogContext) => LumaMenuDialog(
        title: const Text('Sort apps'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final option in const [
              ('default', 'Your order'),
              ('az', 'Name A-Z'),
              ('newest', 'Recently installed'),
            ])
              TvMenuRow(
                title: option.$2,
                selected: sortOrder == option.$1,
                autofocus: sortOrder == option.$1,
                onPressed: () {
                  setState(() => sortOrder = option.$1);
                  unawaited(
                    SharedPreferences.getInstance().then(
                      (prefs) => prefs.setString('all_apps_sort', option.$1),
                    ),
                  );
                  if (scroll?.hasClients ?? false) scroll!.jumpTo(0);
                  Navigator.pop(dialogContext);
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
    );
  }

  /// Every tab opens with the big glass bar. On All it holds the favourites;
  /// on a category tab it holds that category's favourites first, topped up
  /// with the category's other apps, so the bar always fits the tab.
  List<LauncherAppItem> get dockApps {
    final visible = visibleApps;
    final ids = visible.map((a) => a.id).toSet();
    final favourites = widget.favorites
        .where((a) => ids.contains(a.id))
        .take(6)
        .toList();
    if (category == null) return favourites;
    final chosen = favourites.map((a) => a.id).toSet();
    return [
      ...favourites,
      ...visible.where((a) => !chosen.contains(a.id)),
    ].take(6).toList();
  }

  List<LauncherAppItem> get gridApps {
    final dock = dockApps.map((a) => a.id).toSet();
    return visibleApps.where((a) => !dock.contains(a.id)).toList();
  }

  FocusNode node(LauncherAppItem app) => nodes.putIfAbsent(
    app.id,
    () => FocusNode(debugLabel: 'All apps ${app.name}'),
  );

  @override
  void initState() {
    super.initState();
    selected = widget.initialApp;
    columns = widget.columns.clamp(3, 8);
    SharedPreferences.getInstance().then((prefs) {
      final saved = prefs.getString('all_apps_sort');
      if (mounted && const ['default', 'az', 'newest'].contains(saved))
        setState(() => sortOrder = saved!);
    });
  }

  @override
  void dispose() {
    scroll?.dispose();
    backFocus.dispose();
    sortFocus.dispose();
    for (final focus in filterNodes.values) {
      focus.dispose();
    }
    for (final focus in nodes.values) {
      focus.dispose();
    }
    super.dispose();
  }

  void focusApp(LauncherAppItem app) {
    focusContent = true;
    final focus = node(app);
    final dock = dockApps;
    if (dock.any((a) => a.id == app.id)) {
      focus.requestFocus();
      return;
    }
    final index = gridApps.indexWhere((a) => a.id == app.id);
    if (focus.context == null && index >= 0 && (scroll?.hasClients ?? false)) {
      final offset = dockExtent + 24 + (index ~/ columns) * rowExtent;
      scroll!.jumpTo(offset.clamp(0.0, scroll!.position.maxScrollExtent));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && focus.context != null) focus.requestFocus();
      });
    } else {
      focus.requestFocus();
    }
  }

  FocusNode get activeFilter => filterNodes[category ?? 'all']!;

  String categoryFor(LauncherAppItem app) {
    if (tvAppFilters.contains(app.category)) return app.category!;
    for (final section in widget.sections) {
      if (!section.apps.any((item) => item.id == app.id)) continue;
      final label = section.name.toLowerCase();
      if (['video', 'entertainment', 'movies'].contains(label))
        return 'entertainment';
      if (['music', 'audio'].contains(label)) return 'music';
      if (['games', 'gaming'].contains(label)) return 'games';
      if (['utilities', 'tools'].contains(label)) return 'utilities';
    }
    return classifyTvApp(app.id, app.name);
  }

  void selectCategory(String value) {
    setState(() {
      category = value == 'all' ? null : value;
      focusContent = false;
      selected = null;
      if (scroll?.hasClients ?? false) scroll!.jumpTo(0);
    });
    filterNodes[value]!.requestFocus();
  }

  double? appCenter(LauncherAppItem app) {
    final render = node(app).context?.findRenderObject();
    return render is RenderBox && render.hasSize
        ? render.localToGlobal(Offset(render.size.width / 2, 0)).dx
        : null;
  }

  int gridColumnFor(LauncherAppItem app) {
    final center = appCenter(app);
    if (center == null) return 0;
    final lane = (MediaQuery.sizeOf(context).width - 120 + 20) / columns;
    return ((center - 60) / lane).floor().clamp(0, columns - 1);
  }

  LauncherAppItem dockForColumn(int column) {
    final dock = dockApps;
    final target =
        60 +
        (MediaQuery.sizeOf(context).width - 120 + 20) / columns * (column + .5);
    return dock.reduce(
      (a, b) =>
          ((appCenter(a) ?? 0) - target).abs() <=
              ((appCenter(b) ?? 0) - target).abs()
          ? a
          : b,
    );
  }

  @override
  Widget build(BuildContext context) {
    final dock = dockApps, grid = gridApps;
    final palette = MinimalPalette.of(context);
    final first = [...dock, ...grid].firstOrNull;
    final restored =
        visibleApps.where((a) => a.id == selected).firstOrNull ?? first;
    return Scaffold(
      key: const ValueKey('all-apps-page'),
      backgroundColor: palette.glass
          ? palette.background
          : SolidThemeScope.of(context),
      body: CachedWallpaperBackground(
        key: const ValueKey('all-apps-wallpaper'),
        wallpaper: widget.wallpaper,
        cache: widget.wallpaperCache,
        revision: widget.wallpaperRevision,
        enabled: palette.glass || palette.name == 'wallpaper',
        fallback: palette.background,
        child: SafeArea(
          child: FocusTraversalGroup(
            policy: ReadingOrderTraversalPolicy(),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(36, 12, 36, 4),
                  child: Focus(
                    canRequestFocus: false,
                    skipTraversal: true,
                    onKeyEvent: (_, event) {
                      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                        if (event is KeyDownEvent) {
                          final target =
                              visibleApps
                                  .where((app) => app.id == selected)
                                  .firstOrNull ??
                              first;
                          if (target != null) focusApp(target);
                        }
                        return KeyEventResult.handled;
                      }
                      if (event.logicalKey == LogicalKeyboardKey.arrowUp)
                        return KeyEventResult.handled;
                      return KeyEventResult.ignored;
                    },
                    child: Row(
                      children: [
                        IconButton(
                          focusNode: backFocus,
                          autofocus: restored == null && category == null,
                          tooltip: 'Back to Home',
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.arrow_back_rounded),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                for (
                                  var index = 0;
                                  index < tvAppFilters.length;
                                  index++
                                )
                                  Padding(
                                    padding: const EdgeInsets.only(right: 6),
                                    child: Focus(
                                      canRequestFocus: false,
                                      skipTraversal: true,
                                      onKeyEvent: (_, event) {
                                        final direction =
                                            event.logicalKey ==
                                                LogicalKeyboardKey.arrowLeft
                                            ? -1
                                            : event.logicalKey ==
                                                  LogicalKeyboardKey.arrowRight
                                            ? 1
                                            : 0;
                                        if (direction == 0)
                                          return KeyEventResult.ignored;
                                        if (event is KeyDownEvent ||
                                            event is KeyRepeatEvent) {
                                          final next = index + direction;
                                          if (next < 0)
                                            backFocus.requestFocus();
                                          else if (next < tvAppFilters.length)
                                            filterNodes[tvAppFilters[next]]!
                                                .requestFocus();
                                          else
                                            sortFocus.requestFocus();
                                        }
                                        return KeyEventResult.handled;
                                      },
                                      child: TextButton(
                                        key: ValueKey(
                                          'app-filter-${tvAppFilters[index]}',
                                        ),
                                        focusNode:
                                            filterNodes[tvAppFilters[index]],
                                        onFocusChange: (focused) {
                                          if (focused &&
                                              (category ?? 'all') !=
                                                  tvAppFilters[index])
                                            selectCategory(tvAppFilters[index]);
                                        },
                                        onPressed: () =>
                                            selectCategory(tvAppFilters[index]),
                                        style: TextButton.styleFrom(
                                          foregroundColor: palette.text,
                                          backgroundColor:
                                              (category ?? 'all') ==
                                                  tvAppFilters[index]
                                              ? palette.text.withValues(
                                                  alpha: .16,
                                                )
                                              : Colors.transparent,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 12,
                                          ),
                                          shape: const StadiumBorder(),
                                        ),
                                        child: Text(
                                          tvFilterLabel(tvAppFilters[index]),
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight:
                                                (category ?? 'all') ==
                                                    tvAppFilters[index]
                                                ? FontWeight.w600
                                                : FontWeight.w400,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '${visibleApps.length} ${visibleApps.length == 1 ? 'app' : 'apps'}',
                          style: TextStyle(fontSize: 13, color: palette.muted),
                        ),
                        IconButton(
                          focusNode: sortFocus,
                          tooltip: 'Sort apps',
                          onPressed: chooseSort,
                          icon: const Icon(Icons.sort_rounded),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      const gap = 20.0;
                      final labelHeight =
                          (MediaQuery.textScalerOf(context).scale(12) * 1.3)
                              .ceilToDouble() +
                          2;
                      columns = adaptiveAppColumns(
                        viewport: constraints.biggest,
                        appCount: grid.length,
                        preferredColumns: widget.columns,
                        dockExtent: dock.isEmpty ? 0 : 1,
                        labelExtent: labelHeight,
                        matchingDock: true,
                      ).clamp(dock.length, 8);
                      final gridWidth =
                          ((constraints.maxWidth - 120 - gap * (columns - 1)) /
                                  columns)
                              .clamp(56.0, double.infinity);
                      final gridTileHeight =
                          (gridWidth - 8) * 9 / 16 + 8 + 6 + labelHeight;
                      final width = gridWidth;
                      final tileHeight = gridTileHeight;
                      final dockRows = (dock.length / columns).ceil();
                      final dockHeight = dockRows * (tileHeight + gap) - gap;
                      dockExtent = dock.isEmpty ? 0 : dockHeight + 36;
                      rowExtent = gridTileHeight + 24;
                      final initialIndex = grid.indexWhere(
                        (a) => a.id == selected,
                      );
                      scroll ??= ScrollController(
                        initialScrollOffset: initialIndex >= columns
                            ? dockExtent +
                                  24 +
                                  (initialIndex ~/ columns) * rowExtent
                            : 0,
                      );
                      Widget tile(
                        LauncherAppItem app, {
                        required bool inDock,
                        required int index,
                      }) => _MinimalAppTile(
                        key: ValueKey(app.id),
                        app: app,
                        focusNode: node(app),
                        autofocus: focusContent && restored?.id == app.id,
                        reducedMotion: widget.reducedMotion,
                        horizontalOnly: false,
                        compactGlass: true,
                        focusOnlyLabel: true,
                        onPressed: () => widget.onLaunch(app),
                        onOptions: () => widget.onOptions(app),
                        onFocused: () {
                          selected = app.id;
                          widget.onFocused(app);
                        },
                        onLeft: inDock
                            ? () {
                                if (index % columns > 0)
                                  focusApp(dock[index - 1]);
                              }
                            : () {
                                if (index % columns > 0)
                                  focusApp(grid[index - 1]);
                              },
                        onRight: inDock
                            ? () {
                                if (index % columns < columns - 1 &&
                                    index + 1 < dock.length)
                                  focusApp(dock[index + 1]);
                              }
                            : () {
                                if (index % columns < columns - 1 &&
                                    index + 1 < grid.length)
                                  focusApp(grid[index + 1]);
                              },
                        onUp: inDock
                            ? () {
                                if (index >= columns) {
                                  focusApp(dock[index - columns]);
                                } else {
                                  activeFilter.requestFocus();
                                }
                              }
                            : () {
                                if (index >= columns) {
                                  focusApp(grid[index - columns]);
                                } else if (dock.isNotEmpty) {
                                  focusApp(dockForColumn(index));
                                } else {
                                  activeFilter.requestFocus();
                                }
                              },
                        onDown: inDock
                            ? () {
                                if (index + columns < dock.length) {
                                  focusApp(dock[index + columns]);
                                  return;
                                }
                                if (grid.isNotEmpty)
                                  focusApp(
                                    grid[gridColumnFor(
                                      app,
                                    ).clamp(0, grid.length - 1)],
                                  );
                              }
                            : () {
                                if (index ~/ columns <
                                    (grid.length - 1) ~/ columns)
                                  focusApp(
                                    grid[(index + columns).clamp(
                                      0,
                                      grid.length - 1,
                                    )],
                                  );
                              },
                      );
                      return Scrollbar(
                        controller: scroll,
                        thumbVisibility: true,
                        interactive: false,
                        child: ScrollEdgeFade(
                          extent: 24,
                          child: CustomScrollView(
                            key: const PageStorageKey('all-apps-grid'),
                            controller: scroll,
                            slivers: [
                              if (dock.isNotEmpty)
                                SliverPadding(
                                  padding: const EdgeInsets.fromLTRB(
                                    48,
                                    12,
                                    48,
                                    0,
                                  ),
                                  sliver: SliverToBoxAdapter(
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      child: SizedBox(
                                        width:
                                            (dock.length.clamp(0, columns) *
                                                        width +
                                                    (dock.length.clamp(
                                                              0,
                                                              columns,
                                                            ) -
                                                            1) *
                                                        gap +
                                                    24)
                                                .clamp(
                                                  0.0,
                                                  constraints.maxWidth - 96,
                                                ),
                                        child: LumaGlassPanel(
                                          key: const ValueKey(
                                            'all-apps-favourites-dock',
                                          ),
                                          enabled: palette.glass,
                                          clipChild: false,
                                          radius: 26,
                                          child: Material(
                                            color: palette.glass
                                                ? Colors.transparent
                                                : palette.surface.withValues(
                                                    alpha: .90,
                                                  ),
                                            borderRadius: BorderRadius.circular(
                                              26,
                                            ),
                                            child: Padding(
                                              padding: const EdgeInsets.all(12),
                                              child: SizedBox(
                                                height: dockHeight,
                                                child: Wrap(
                                                  spacing: gap,
                                                  runSpacing: gap,
                                                  children: [
                                                    for (
                                                      var index = 0;
                                                      index < dock.length;
                                                      index++
                                                    ) ...[
                                                      SizedBox(
                                                        width: width,
                                                        height: tileHeight,
                                                        child: tile(
                                                          dock[index],
                                                          inDock: true,
                                                          index: index,
                                                        ),
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              if (grid.isNotEmpty)
                                SliverPadding(
                                  padding: const EdgeInsets.fromLTRB(
                                    60,
                                    24,
                                    60,
                                    40,
                                  ),
                                  sliver: SliverGrid(
                                    gridDelegate:
                                        SliverGridDelegateWithFixedCrossAxisCount(
                                          crossAxisCount: columns,
                                          mainAxisExtent: gridTileHeight,
                                          crossAxisSpacing: gap,
                                          mainAxisSpacing: 24,
                                        ),
                                    delegate: SliverChildBuilderDelegate(
                                      (_, index) => tile(
                                        grid[index],
                                        inDock: false,
                                        index: index,
                                      ),
                                      childCount: grid.length,
                                    ),
                                  ),
                                ),
                              // A category whose apps all fit in its bar
                              // needs no message underneath.
                              if (grid.isEmpty &&
                                  (category == null || dock.isEmpty))
                                SliverFillRemaining(
                                  hasScrollBody: false,
                                  child: Center(
                                    child: Text(
                                      // The favourites bar shows on every
                                      // tab, so "all in Favourites" only
                                      // applies when this tab has apps.
                                      dock.isNotEmpty
                                          ? 'All your apps are in Favourites'
                                          : category == null
                                          ? 'No apps available'
                                          : category == 'games'
                                          ? 'No games installed'
                                          : 'No ${tvFilterLabel(category!).toLowerCase()} apps installed',
                                      style: TextStyle(color: palette.muted),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MinimalControl extends StatelessWidget {
  const _MinimalControl({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.focusNode,
    this.autofocus = false,
  });
  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final FocusNode? focusNode;
  final bool autofocus;
  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    focusNode: focusNode,
    autofocus: autofocus,
    onPressed: onPressed,
    icon: Icon(icon, size: 25),
    style: ButtonStyle(
      animationDuration: motionReduced(context)
          ? Duration.zero
          : lumaFocusDuration,
      foregroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.focused)
            ? Colors.white
            : MinimalPalette.of(context).muted,
      ),
      backgroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.focused)
            ? MinimalPalette.of(context).surface
            : Colors.transparent,
      ),
      side: WidgetStateProperty.resolveWith(
        (states) => BorderSide(
          color: states.contains(WidgetState.focused)
              ? MinimalPalette.of(context).text
              : Colors.transparent,
        ),
      ),
      shape: WidgetStatePropertyAll(
        RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
  );
}

class _MinimalAppTile extends StatefulWidget {
  const _MinimalAppTile({
    super.key,
    required this.app,
    required this.onPressed,
    required this.onOptions,
    required this.onFocused,
    this.focusNode,
    this.autofocus = false,
    this.reducedMotion = false,
    this.horizontalOnly = false,
    this.compactGlass = false,
    this.focusOnlyLabel = false,
    this.tvStyle = false,
    this.onDown,
    this.onUp,
    this.onRight,
    this.onLeft,
    this.moving = false,
    this.onMove,
    this.onFinishMove,
  });
  final bool moving;
  final ValueChanged<int>? onMove;
  final VoidCallback? onFinishMove;
  final LauncherAppItem app;
  final FocusNode? focusNode;
  final bool autofocus,
      reducedMotion,
      horizontalOnly,
      compactGlass,
      focusOnlyLabel,
      tvStyle;
  final VoidCallback onPressed, onOptions, onFocused;
  final VoidCallback? onDown, onUp, onRight, onLeft;
  @override
  State<_MinimalAppTile> createState() => _MinimalAppTileState();
}

class _MinimalAppTileState extends State<_MinimalAppTile> {
  final owned = FocusNode();
  final _artTarget = GlobalKey();
  FocusNode get focus => widget.focusNode ?? owned;
  late Future<ImageProvider?> artwork;
  bool focused = false, held = false, longPress = false;
  bool _pointerRequestedFocus = false;
  Timer? hold;
  @override
  void initState() {
    super.initState();
    load();
  }

  void load() {
    artwork = _loadArtwork();
  }

  Future<ImageProvider?> _loadArtwork() async {
    final pack = tvIconPackArtwork(widget.app.id, widget.app.name);
    if (pack != null) return pack;
    try {
      final banner =
          await (widget.app.loadArtwork?.call() ??
              widget.app.artwork ??
              Future<ImageProvider?>.value(null));
      if (banner != null) return banner;
    } catch (_) {
      // Apps without TV artwork keep their original icon.
    }
    try {
      return await (widget.app.loadIcon?.call() ??
          widget.app.icon ??
          Future<ImageProvider?>.value(null));
    } catch (_) {
      return null;
    }
  }

  @override
  void didUpdateWidget(_MinimalAppTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.app, widget.app)) load();
  }

  @override
  void dispose() {
    hold?.cancel();
    owned.dispose();
    super.dispose();
  }

  void changed(bool value) {
    final reveal = !_pointerRequestedFocus;
    _pointerRequestedFocus = false;
    setState(() => focused = value);
    reportFocusTarget(context, _artTarget, value);
    if (!value) {
      hold?.cancel();
      held = false;
      return;
    }
    widget.onFocused();
    // Pointer hover must not scroll the viewport beneath the cursor. Remote
    // navigation still reveals off-screen apps when their focus changes.
    if (!reveal) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !focus.hasFocus) return;
      final duration = motionReduced(context, widget.reducedMotion)
          ? Duration.zero
          : lumaFocusDuration;
      if (widget.horizontalOnly) {
        final render = context.findRenderObject();
        if (render != null)
          revealHorizontalFocus(
            context,
            render,
            reduced: motionReduced(context, widget.reducedMotion),
          );
      } else {
        Scrollable.ensureVisible(
          context,
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
          duration: duration,
          curve: lumaFocusCurve,
        );
      }
    });
  }

  void _focusFromPointer() {
    if (focus.hasFocus) return;
    _pointerRequestedFocus = true;
    focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = motionReduced(context, widget.reducedMotion);
    return RepaintBoundary(
      child: Semantics(
        button: true,
        selected: focused,
        label: widget.app.name,
        child: Focus(
          focusNode: focus,
          autofocus: widget.autofocus,
          onFocusChange: changed,
          onKeyEvent: (_, event) {
            _pointerRequestedFocus = false;
            final key = event.logicalKey;
            if (widget.moving) {
              if (key == LogicalKeyboardKey.arrowLeft ||
                  key == LogicalKeyboardKey.arrowRight) {
                if (event is KeyDownEvent || event is KeyRepeatEvent) {
                  widget.onMove?.call(
                    key == LogicalKeyboardKey.arrowLeft ? -1 : 1,
                  );
                }
                return KeyEventResult.handled;
              }
              if ([
                LogicalKeyboardKey.enter,
                LogicalKeyboardKey.numpadEnter,
                LogicalKeyboardKey.select,
                LogicalKeyboardKey.space,
                LogicalKeyboardKey.gameButtonA,
                LogicalKeyboardKey.escape,
                LogicalKeyboardKey.goBack,
                LogicalKeyboardKey.gameButtonB,
                LogicalKeyboardKey.contextMenu,
              ].contains(key)) {
                if (event is KeyUpEvent) widget.onFinishMove?.call();
                return KeyEventResult.handled;
              }
              if (key == LogicalKeyboardKey.arrowUp ||
                  key == LogicalKeyboardKey.arrowDown) {
                return KeyEventResult.handled;
              }
            }
            final direction = key == LogicalKeyboardKey.arrowDown
                ? widget.onDown
                : key == LogicalKeyboardKey.arrowUp
                ? widget.onUp
                : key == LogicalKeyboardKey.arrowRight
                ? widget.onRight
                : key == LogicalKeyboardKey.arrowLeft
                ? widget.onLeft
                : null;
            if (direction != null) {
              if (event is KeyDownEvent || event is KeyRepeatEvent) direction();
              return KeyEventResult.handled;
            }
            if ([
              LogicalKeyboardKey.enter,
              LogicalKeyboardKey.numpadEnter,
              LogicalKeyboardKey.select,
              LogicalKeyboardKey.space,
              LogicalKeyboardKey.gameButtonA,
            ].contains(key)) {
              if (event is KeyDownEvent) {
                held = true;
                longPress = false;
                hold?.cancel();
                hold = Timer(Duration(milliseconds: 600), () {
                  if (mounted && held) longPress = true;
                });
              } else if (event is KeyUpEvent && held) {
                held = false;
                hold?.cancel();
                if (longPress) {
                  widget.onOptions();
                } else {
                  widget.onPressed();
                }
              }
              return KeyEventResult.handled;
            }
            if (event is KeyDownEvent &&
                key == LogicalKeyboardKey.contextMenu) {
              widget.onOptions();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            onHover: (_) => _focusFromPointer(),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (_) => _focusFromPointer(),
              onTap: widget.onPressed,
              onLongPress: widget.onOptions,
              child: AppArtworkBuilder(
                id: widget.app.id,
                original: () => installedAppArtwork(widget.app),
                future: artwork,
                builder: (context, snapshot) {
                  if (focused)
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted && focus.hasFocus)
                        reportFocusTarget(context, _artTarget, true);
                    });
                  return LayoutBuilder(
                    builder: (context, constraints) {
                      final side = (constraints.maxWidth - 8).clamp(
                        40.0,
                        widget.focusOnlyLabel ? double.infinity : 360.0,
                      );
                      final width = side;
                      final height = side * 9 / 16;
                      // Bucket by displayed physical size so a small dock tile
                      // does not decode/upload a 1280x720 texture.
                      final decodeWidth =
                          ((side *
                                          MediaQuery.devicePixelRatioOf(
                                            context,
                                          ) *
                                          1.15 /
                                          64)
                                      .ceil() *
                                  64)
                              .clamp(64, 1280);
                      final art = RepaintBoundary(
                        child: StaticPaintCache(
                          child: ClipRSuperellipse(
                            borderRadius: BorderRadius.circular(
                              widget.tvStyle ? 10 : lumaCardRadius,
                            ),
                            clipBehavior: Clip.hardEdge,
                            child: ColoredBox(
                              color: MinimalPalette.of(context).surface,
                              child: snapshot.data != null
                                  ? Image(
                                      image: ResizeImage(
                                        snapshot.data!,
                                        width: decodeWidth,
                                        allowUpscaling: false,
                                      ),
                                      filterQuality: FilterQuality.medium,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) =>
                                          const Center(
                                            child: Icon(Icons.apps_rounded),
                                          ),
                                    )
                                  : ColoredBox(
                                      color: MinimalPalette.of(context).surface,
                                      child: Center(
                                        child: Icon(
                                          Icons.apps_rounded,
                                          color: MinimalPalette.of(
                                            context,
                                          ).muted,
                                        ),
                                      ),
                                    ),
                            ),
                          ),
                        ),
                      );
                      return DecoratedBox(
                        key: ValueKey(
                          'glass-favourite-highlight-${widget.app.id}',
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(100),
                          color: Colors.transparent,
                        ),
                        child: Column(
                          children: [
                            SizedBox(
                              key: ValueKey(
                                'minimal-card-motion-slot-${widget.app.id}',
                              ),
                              width: side,
                              // Reserve the hover lift inside each tile, rather
                              // than painting above the scroll viewport.
                              height: height + (widget.tvStyle ? 20 : 8),
                              child: Align(
                                alignment: widget.tvStyle
                                    ? Alignment.center
                                    : Alignment.bottomCenter,
                                child: SizedBox(
                                  key: _artTarget,
                                  width: width,
                                  height: height,
                                  child: TweenAnimationBuilder<double>(
                                    tween: Tween(end: focused ? 1 : 0),
                                    duration: reduce
                                        ? Duration.zero
                                        : lumaFocusDuration,
                                    curve: lumaFocusCurve,
                                    child: Container(
                                      key: ValueKey(
                                        'minimal-focus-${widget.app.id}',
                                      ),
                                      foregroundDecoration: widget.moving
                                          ? BoxDecoration(
                                              borderRadius:
                                                  BorderRadius.circular(14),
                                              border: Border.all(
                                                color: Colors.white,
                                                width: 2,
                                              ),
                                            )
                                          : null,
                                      child: art,
                                    ),
                                    builder: (_, value, child) => Transform.translate(
                                      offset: Offset(
                                        0,
                                        reduce
                                            ? 0
                                            : -(widget.tvStyle ? 0 : 6) * value,
                                      ),
                                      child: Transform.scale(
                                        scale: reduce
                                            ? 1
                                            : 1 +
                                                  (widget.tvStyle
                                                          ? .035
                                                          : .05) *
                                                      value,
                                        child: widget.tvStyle
                                            ? DecoratedBox(
                                                decoration: ShapeDecoration(
                                                  shape:
                                                      RoundedSuperellipseBorder(
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              10,
                                                            ),
                                                        side: BorderSide(
                                                          color: Colors.white
                                                              .withValues(
                                                                alpha:
                                                                    .25 * value,
                                                              ),
                                                          width: .65,
                                                        ),
                                                      ),
                                                ),
                                                child: child,
                                              )
                                            : child,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(
                              height: widget.tvStyle
                                  ? 10
                                  : widget.compactGlass
                                  ? 6
                                  : 14,
                            ),
                            ExcludeSemantics(
                              child: AnimatedOpacity(
                                opacity: !widget.focusOnlyLabel || focused
                                    ? 1
                                    : 0,
                                duration: reduce
                                    ? Duration.zero
                                    : const Duration(milliseconds: 140),
                                child: Text(
                                  widget.app.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: widget.compactGlass ? 12 : 14,
                                    shadows: widget.focusOnlyLabel
                                        ? const [
                                            Shadow(
                                              color: Color(0xaa000000),
                                              blurRadius: 4,
                                              offset: Offset(0, 1),
                                            ),
                                          ]
                                        : null,
                                    height: 1.3,
                                    color: MinimalPalette.of(
                                      context,
                                    ).text.withValues(alpha: focused ? 1 : .72),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MinimalHeaderDelegate extends SliverPersistentHeaderDelegate {
  _MinimalHeaderDelegate({required this.child, this.extent = 84});
  final Widget child;
  final double extent;
  @override
  double get minExtent => extent;
  @override
  double get maxExtent => extent;
  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => ClipRect(child: child);
  @override
  bool shouldRebuild(_MinimalHeaderDelegate oldDelegate) =>
      child != oldDelegate.child || extent != oldDelegate.extent;
}

class _DockScrollFade extends StatelessWidget {
  const _DockScrollFade({required this.controller, required this.child});
  final ScrollController controller;
  final Widget child;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    child: child,
    builder: (_, child) {
      final opacity = controller.hasClients
          ? (1 - controller.offset / 160).clamp(0.0, 1.0)
          : 1.0;
      return IgnorePointer(
        ignoring: opacity == 0,
        child: Opacity(
          key: const ValueKey('home-dock-opacity'),
          opacity: opacity,
          child: child,
        ),
      );
    },
  );
}

class _FocusedUtilityLabel extends StatefulWidget {
  const _FocusedUtilityLabel({required this.label, required this.child});
  final String label;
  final Widget child;
  @override
  State<_FocusedUtilityLabel> createState() => _FocusedUtilityLabelState();
}

class _FocusedUtilityLabelState extends State<_FocusedUtilityLabel> {
  bool focused = false;
  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    onFocusChange: (value) {
      if (focused != value) setState(() => focused = value);
    },
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        widget.child,
        if (widget.label != 'Clock')
          Positioned(
            top: 48,
            left: -26,
            right: -26,
            child: IgnorePointer(
              child: AnimatedSwitcher(
                duration: motionReduced(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 120),
                child: focused
                    ? Text(
                        widget.label == 'Search apps'
                            ? 'Search'
                            : widget.label == 'Voice search'
                            ? 'Voice'
                            : widget.label,
                        key: ValueKey('utility-label-${widget.label}'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          color: MinimalPalette.of(context).text,
                          // Drawn straight on the wallpaper: keep it legible
                          // over white skies like the dock's focus label.
                          shadows: const [
                            Shadow(
                              color: Color(0xaa000000),
                              blurRadius: 4,
                              offset: Offset(0, 1),
                            ),
                          ],
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          ),
      ],
    ),
  );
}

/// Bell for the home top bar; a small count badge appears when there are
/// notifications.
class _NotificationBell extends StatelessWidget {
  const _NotificationBell({required this.count});
  final int count;
  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 26,
    child: Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        Icon(
          count > 0
              ? Icons.notifications_rounded
              : Icons.notifications_none_rounded,
          size: 22,
        ),
        if (count > 0)
          Positioned(
            key: const ValueKey('notification-badge'),
            top: -3,
            right: -5,
            child: Container(
              constraints: const BoxConstraints(minWidth: 16),
              height: 16,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                count > 9 ? '9+' : '$count',
                style: const TextStyle(
                  fontSize: 10,
                  height: 1,
                  fontWeight: FontWeight.w700,
                  color: Color(0xff0b0c10),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class _HomePillButton extends StatelessWidget {
  const _HomePillButton({
    required this.glass,
    required this.tooltip,
    required this.child,
    required this.onPressed,
    this.focusNode,
    this.buttonKey,
    this.bare = false,
  });
  final bool glass;
  final bool bare;
  final String tooltip;
  final Widget child;
  final VoidCallback onPressed;
  final FocusNode? focusNode;
  final Key? buttonKey;
  @override
  Widget build(BuildContext context) => _FocusedUtilityLabel(
    label: tooltip,
    child: _GlassFocusLift(
      scale: tooltip == 'Clock' ? 1.1 : 1.22,
      child: LiquidGlassV2(
        enabled: glass && !bare,
        compact: true,
        radius: 100,
        band: WallpaperBand.top,
        child: Tooltip(
          message: tooltip,
          excludeFromSemantics: true,
          child: TextButton(
            key: buttonKey,
            focusNode: focusNode,
            onPressed: onPressed,
            style: ButtonStyle(
              animationDuration: motionReduced(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 140),
              splashFactory: NoSplash.splashFactory,
              overlayColor: WidgetStateProperty.resolveWith(
                (states) => Colors.white.withValues(
                  alpha: states.contains(WidgetState.pressed)
                      ? .16
                      : states.contains(WidgetState.focused)
                      ? 0
                      : states.contains(WidgetState.hovered)
                      ? .07
                      : 0,
                ),
              ),
              minimumSize: const WidgetStatePropertyAll(Size(44, 44)),
              fixedSize: tooltip == 'Clock'
                  ? null
                  : const WidgetStatePropertyAll(Size(44, 44)),
              padding: WidgetStatePropertyAll(
                EdgeInsets.symmetric(
                  horizontal: tooltip == 'Clock' ? (bare ? 6 : 22) : 0,
                  vertical: tooltip == 'Clock' ? 6 : 0,
                ),
              ),
              foregroundColor: WidgetStatePropertyAll(
                MinimalPalette.of(context).text,
              ),
              backgroundColor: WidgetStatePropertyAll(
                glass || bare
                    ? Colors.transparent
                    : MinimalPalette.of(context).surface.withValues(alpha: .82),
              ),
              shape: WidgetStateProperty.resolveWith((states) {
                // Focus brightens the glass and gives it a thin light rim;
                // the lift around the button makes it grow.
                final side = BorderSide(
                  color: states.contains(WidgetState.focused)
                      ? Colors.transparent
                      : glass || bare
                      ? Colors.transparent
                      : Colors.white.withValues(alpha: .15),
                  width: states.contains(WidgetState.focused)
                      ? 0
                      : glass || bare
                      ? 0
                      : 1,
                );
                return tooltip == 'Clock'
                    ? StadiumBorder(side: side)
                    : CircleBorder(side: side);
              }),
            ),
            child: Semantics(label: tooltip, child: child),
          ),
        ),
      ),
    ),
  );
}

/// Grows its child a little while anything inside it has focus. A plain
/// transform, so it never repaints the glass.
class _GlassFocusLift extends StatefulWidget {
  const _GlassFocusLift({required this.child, this.scale = 1.14});
  final Widget child;
  final double scale;
  @override
  State<_GlassFocusLift> createState() => _GlassFocusLiftState();
}

class _GlassFocusLiftState extends State<_GlassFocusLift> {
  bool focused = false;
  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    skipTraversal: true,
    onFocusChange: (value) => setState(() => focused = value),
    child: AnimatedScale(
      scale: focused ? widget.scale : 1,
      duration: motionReduced(context)
          ? Duration.zero
          : const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      child: widget.child,
    ),
  );
}
