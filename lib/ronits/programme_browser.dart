import 'package:flutter/material.dart';
import 'remote_navigation.dart';
import 'package:flutter/services.dart';
import 'programme_library.dart';
import 'programme_rail.dart';
import 'glass_surface.dart';
import 'menu_dialog.dart';
import 'motion.dart';
import 'focus_feedback.dart';
import 'programme_source_icon.dart';

Future<void> showProgrammeSources(BuildContext context) async {
  final library = ProgrammeLibrary.shared;
  await library.ready();
  if (!context.mounted) return;
  await showLumaDialog<void>(
    context: context,
    builder: (dialogContext) => ListenableBuilder(
      listenable: library,
      builder: (_, __) {
        final entries = library.availableSources.entries.toList()
          ..sort((a, b) => a.value.compareTo(b.value));
        return LumaMenuDialog(
          title: const Text('From your apps · Sources'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Choose the apps you want on Home. Programme cards depend on what each app shares with Android TV.',
              ),
              const SizedBox(height: 12),
              if (entries.isEmpty)
                Text(
                  !library.sourceAccessAllowed
                      ? 'Allow content access to find programme cards from your apps.'
                      : 'No apps are sharing programme cards yet. Open a streaming app, then refresh.',
                ),
              for (final entry in entries)
                TvMenuRow(
                  key: ValueKey('programme-source-${entry.key}'),
                  autofocus: entry == entries.first,
                  title: entry.value,
                  subtitle: library.sourceStatus(entry.key),
                  selected: !library.disabledSources.contains(entry.key),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ProgrammeSourceIcon(source: entry.key, name: entry.value),
                      const SizedBox(width: 12),
                      Icon(
                        !library.disabledSources.contains(entry.key)
                            ? Icons.check_box_rounded
                            : Icons.check_box_outline_blank_rounded,
                      ),
                    ],
                  ),
                  onPressed: () async {
                    try {
                      await library.setSourceEnabled(
                        entry.key,
                        library.disabledSources.contains(entry.key),
                      );
                    } catch (_) {
                      if (dialogContext.mounted)
                        ScaffoldMessenger.maybeOf(dialogContext)?.showSnackBar(
                          const SnackBar(
                            content: Text('Could not save app sources.'),
                          ),
                        );
                    }
                  },
                ),
            ],
          ),
          actions: [
            if (!library.sourceAccessAllowed &&
                library.requestSourceAccess != null)
              TextButton(
                onPressed: () async {
                  try {
                    await library.requestSourceAccess!();
                  } catch (_) {
                    if (dialogContext.mounted)
                      ScaffoldMessenger.maybeOf(dialogContext)?.showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Could not open content access. Please try again.',
                          ),
                        ),
                      );
                  }
                },
                child: const Text('Allow content access'),
              ),
            if (library.refreshSources != null)
              TextButton(
                onPressed: () async {
                  try {
                    await library.refreshSources!();
                  } catch (_) {
                    if (dialogContext.mounted)
                      ScaffoldMessenger.maybeOf(dialogContext)?.showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Could not refresh programme sources. Please try again.',
                          ),
                        ),
                      );
                  }
                },
                child: const Text('Refresh'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Done'),
            ),
          ],
        );
      },
    ),
  );
}

Future<void> launchProgramme(
  BuildContext context,
  ProgrammeEntry entry, {
  bool appOnly = false,
}) async {
  if (entry.asset != null &&
      entry.item.packageName?.startsWith('preview.') == true) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(
        content: Text(
          'Sample programme · playback is available on Android through supported apps.',
        ),
      ),
    );
    return;
  }
  try {
    final success =
        await ProgrammeLibrary.shared.launch?.call(entry, appOnly) ?? false;
    if (!success && context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: const Text('This programme could not be opened.'),
          action: appOnly
              ? null
              : SnackBarAction(
                  label: 'Open app',
                  onPressed: () =>
                      launchProgramme(context, entry, appOnly: true),
                ),
        ),
      );
    }
  } catch (_) {
    if (context.mounted)
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('The streaming app could not be opened.')),
      );
  }
}

Future<void> programmeOptions(
  BuildContext context,
  ProgrammeEntry entry, {
  VoidCallback? onHidden,
}) => showLumaDialog<void>(
  context: context,
  builder: (dialogContext) => ListenableBuilder(
    listenable: ProgrammeLibrary.shared,
    builder: (_, __) {
      final library = ProgrammeLibrary.shared;
      return LumaMenuDialog(
        title: Text(entry.item.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              entry.provider,
              style: TextStyle(color: MinimalPalette.of(context).muted),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              autofocus: true,
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Resume / play'),
              onPressed: () {
                Navigator.pop(dialogContext);
                launchProgramme(context, entry);
              },
            ),
            TextButton.icon(
              icon: const Icon(Icons.info_outline_rounded),
              label: const Text('Details'),
              onPressed: () {
                Navigator.pop(dialogContext);
                showProgrammeDetails(context, entry);
              },
            ),
            TextButton.icon(
              icon: const Icon(Icons.open_in_new_rounded),
              label: const Text('Open streaming app'),
              onPressed: () {
                Navigator.pop(dialogContext);
                launchProgramme(context, entry, appOnly: true);
              },
            ),
            TextButton.icon(
              icon: Icon(
                library.saved.containsKey(entry.key)
                    ? Icons.bookmark_remove_outlined
                    : Icons.bookmark_add_outlined,
              ),
              label: Text(
                library.saved.containsKey(entry.key)
                    ? 'Remove from watchlist'
                    : 'Save to watchlist',
              ),
              onPressed: () async {
                try {
                  await library.toggleSaved(entry);
                } catch (_) {
                  if (dialogContext.mounted)
                    ScaffoldMessenger.maybeOf(dialogContext)?.showSnackBar(
                      const SnackBar(
                        content: Text('Could not save watchlist.'),
                      ),
                    );
                }
              },
            ),
            TextButton.icon(
              icon: const Icon(Icons.visibility_off_outlined),
              label: const Text('Hide title'),
              onPressed: () async {
                final messenger = ScaffoldMessenger.maybeOf(context);
                Navigator.pop(dialogContext);
                try {
                  await library.setHidden(entry, true);
                  onHidden?.call();
                  if (messenger?.mounted == true)
                    messenger!.showSnackBar(
                      SnackBar(
                        content: Text('${entry.item.title} hidden'),
                        action: SnackBarAction(
                          label: 'Undo',
                          onPressed: () => library.setHidden(entry, false),
                        ),
                      ),
                    );
                } catch (_) {
                  if (messenger?.mounted == true)
                    messenger!.showSnackBar(
                      const SnackBar(
                        content: Text('Could not save hidden titles.'),
                      ),
                    );
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
      );
    },
  ),
);

Future<void> showProgrammeDetails(BuildContext context, ProgrammeEntry entry) =>
    showLumaDialog<void>(
      context: context,
      builder: (_) => ProgrammeDetails(entry: entry),
    );

class ProgrammeDetails extends StatefulWidget {
  const ProgrammeDetails({super.key, required this.entry});
  final ProgrammeEntry entry;
  @override
  State<ProgrammeDetails> createState() => _ProgrammeDetailsState();
}

class _ProgrammeDetailsState extends State<ProgrammeDetails> {
  late final Future<ImageProvider?> artwork = widget.entry.asset != null
      ? Future.value(AssetImage(widget.entry.asset!))
      : ProgrammeLibrary.shared.loadArtwork?.call(widget.entry) ??
            Future.value(null);
  bool launching = false, saving = false;
  String? message;
  Future<void> play({bool appOnly = false}) async {
    if (launching) return;
    setState(() {
      launching = true;
      message = null;
    });
    try {
      final opened =
          await ProgrammeLibrary.shared.launch?.call(widget.entry, appOnly) ??
          false;
      if (!mounted) return;
      setState(
        () => message = opened
            ? null
            : 'This title could not open. Try Open streaming app.',
      );
    } catch (_) {
      if (mounted)
        setState(
          () => message = 'The streaming app could not open. Please try again.',
        );
    } finally {
      if (mounted) setState(() => launching = false);
    }
  }

  Future<void> save() async {
    if (saving) return;
    setState(() {
      saving = true;
      message = null;
    });
    try {
      await ProgrammeLibrary.shared.toggleSaved(widget.entry);
      if (mounted)
        setState(
          () => message =
              ProgrammeLibrary.shared.saved.containsKey(widget.entry.key)
              ? 'Saved to watchlist'
              : 'Removed from watchlist',
        );
    } catch (_) {
      if (mounted)
        setState(
          () => message = 'Could not save your watchlist. Please try again.',
        );
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final progress = entry.item.progressPercent;
    return LumaMenuDialog(
      title: Text(entry.item.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRSuperellipse(
            borderRadius: BorderRadius.circular(lumaCardRadius),
            child: SizedBox(
              height: 165,
              child: FutureBuilder<ImageProvider?>(
                future: artwork,
                builder: (_, snapshot) {
                  final fallback = ColoredBox(
                    color: const Color(0xff192633),
                    child: Center(
                      child: Icon(
                        snapshot.connectionState == ConnectionState.waiting
                            ? Icons.image_outlined
                            : Icons.movie_outlined,
                        color: Colors.white38,
                        size: 44,
                      ),
                    ),
                  );
                  return snapshot.data == null
                      ? fallback
                      : Image(
                          image: ResizeImage(
                            snapshot.data!,
                            width: 960,
                            allowUpscaling: false,
                          ),
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => fallback,
                        );
                },
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            entry.provider,
            style: const TextStyle(fontSize: 13, color: Color(0xffd4dce5)),
          ),
          const SizedBox(height: 8),
          Text(
            entry.item.description?.trim().isNotEmpty == true
                ? entry.item.description!
                : 'This app has not shared a description.',
            style: const TextStyle(fontSize: 14, height: 1.4),
          ),
          if (progress != null && progress > 0) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: (progress / 100).clamp(0, 1),
              semanticsLabel: 'Watch progress',
            ),
            const SizedBox(height: 6),
            Text('$progress% watched'),
          ],
          const SizedBox(height: 12),
          TvMenuRow(
            autofocus: true,
            title: launching
                ? 'Opening...'
                : progress != null && progress > 0
                ? 'Resume'
                : 'Play',
            icon: Icons.play_arrow_rounded,
            onPressed: () => play(),
          ),
          ListenableBuilder(
            listenable: ProgrammeLibrary.shared,
            builder: (_, __) => TvMenuRow(
              title: saving
                  ? 'Saving...'
                  : ProgrammeLibrary.shared.saved.containsKey(entry.key)
                  ? 'Remove from watchlist'
                  : 'Save to watchlist',
              icon: ProgrammeLibrary.shared.saved.containsKey(entry.key)
                  ? Icons.bookmark_rounded
                  : Icons.bookmark_add_outlined,
              onPressed: save,
            ),
          ),
          TvMenuRow(
            title: 'Open streaming app',
            icon: Icons.open_in_new_rounded,
            onPressed: () => play(appOnly: true),
          ),
          TvMenuRow(
            title: 'More options',
            icon: Icons.more_horiz_rounded,
            onPressed: () => programmeOptions(
              context,
              entry,
              onHidden: () {
                if (mounted) Navigator.pop(context);
              },
            ),
          ),
          if (message != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Semantics(liveRegion: true, child: Text(message!)),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Back'),
        ),
      ],
    );
  }
}

class LibraryProgrammeCard extends StatefulWidget {
  const LibraryProgrammeCard({
    super.key,
    required this.entry,
    this.focusNode,
    this.compact = false,
  });
  final bool compact;
  final ProgrammeEntry entry;
  final FocusNode? focusNode;
  @override
  State<LibraryProgrammeCard> createState() => _LibraryProgrammeCardState();
}

class _LibraryProgrammeCardState extends State<LibraryProgrammeCard> {
  Future<ImageProvider?>? artwork;
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    artwork = widget.entry.asset != null
        ? Future.value(AssetImage(widget.entry.asset!))
        : ProgrammeLibrary.shared.loadArtwork?.call(widget.entry);
  }

  @override
  void didUpdateWidget(LibraryProgrammeCard old) {
    super.didUpdateWidget(old);
    if (old.entry != widget.entry ||
        old.entry.item.posterUri != widget.entry.item.posterUri ||
        old.entry.item.backdropUri != widget.entry.item.backdropUri ||
        old.entry.asset != widget.entry.asset)
      _load();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<ImageProvider?>(
    future: artwork,
    builder: (_, image) => ProgrammeCard(
      compact: widget.compact,
      focusNode: widget.focusNode,
      title: widget.entry.item.title,
      provider: widget.entry.provider,
      providerId: widget.entry.item.packageName,
      progress: widget.entry.item.progressPercent == null
          ? null
          : widget.entry.item.progressPercent! / 100,
      artwork: image.data,
      loading: image.connectionState == ConnectionState.waiting,
      onPressed: () => launchProgramme(context, widget.entry),
      onOptions: () => showProgrammeDetails(context, widget.entry),
    ),
  );
}

/// The large panel above the Home row: the programme's artwork, softly shaded
/// on the left, with its app, title and progress. It changes with focus and
/// is not itself focusable; OK on the card below plays the programme.
class _Spotlight extends StatelessWidget {
  const _Spotlight({required this.entry, required this.artworkFor});
  final ProgrammeEntry entry;
  final Future<ImageProvider?> Function(ProgrammeEntry) artworkFor;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final progress = entry.item.progressPercent;
    return SizedBox(
      height: (size.height * .40).clamp(220.0, 460.0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: AnimatedSwitcher(
          duration: motionReduced(context)
              ? Duration.zero
              : const Duration(milliseconds: 280),
          child: Stack(
            key: ValueKey('spotlight-${entry.key}'),
            fit: StackFit.expand,
            children: [
              const ColoredBox(color: Color(0xff15181d)),
              FutureBuilder<ImageProvider?>(
                future: artworkFor(entry),
                builder: (_, image) => image.data == null
                    ? const SizedBox.shrink()
                    : Image(
                        image: ResizeImage.resizeIfNeeded(
                          (size.width * MediaQuery.devicePixelRatioOf(context))
                              .round(),
                          null,
                          image.data!,
                        ),
                        fit: BoxFit.cover,
                        alignment: Alignment.topCenter,
                        gaplessPlayback: true,
                        errorBuilder: (_, _, _) => const SizedBox.shrink(),
                      ),
              ),
              // Shade where the text sits, clear over the artwork.
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [Color(0xd9000000), Color(0x00000000)],
                    stops: [0, .62],
                  ),
                ),
              ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Color(0x99000000), Color(0x00000000)],
                    stops: [0, .5],
                  ),
                ),
              ),
              Positioned(
                left: 36,
                bottom: 32,
                width: size.width * .42,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      entry.provider.toUpperCase(),
                      key: const ValueKey('spotlight-provider'),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.4,
                        color: Colors.white.withValues(alpha: .72),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      entry.item.title,
                      key: const ValueKey('spotlight-title'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 34,
                        height: 1.1,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -.4,
                        color: Colors.white,
                      ),
                    ),
                    if (progress != null && progress > 0) ...[
                      const SizedBox(height: 14),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: SizedBox(
                          width: 160,
                          height: 3,
                          child: LinearProgressIndicator(
                            value: (progress / 100).clamp(0.0, 1.0),
                            backgroundColor: Colors.white.withValues(
                              alpha: .22,
                            ),
                            valueColor: const AlwaysStoppedAnimation(
                              Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shared TV and browser shelf; filtering never queries remote catalogues.
class ProgrammeShelf extends StatefulWidget {
  const ProgrammeShelf({
    super.key,
    this.title = 'Continue watching',
    this.caption,
    this.spotlight = false,
  });
  final String title;
  final String? caption;

  /// Home layout: a large artwork panel for the focused programme above a
  /// slim row of cards, like a TV top shelf.
  final bool spotlight;
  @override
  State<ProgrammeShelf> createState() => _ProgrammeShelfState();
}

class _ProgrammeShelfState extends State<ProgrammeShelf> {
  String? provider;

  /// The programme shown in the spotlight: the focused card, or the first.
  String? spotKey;
  final _artwork = <String, Future<ImageProvider?>>{};
  Future<ImageProvider?> artworkFor(ProgrammeEntry entry) =>
      _artwork[entry.key] ??= entry.asset != null
      ? Future.value(AssetImage(entry.asset!))
      : (ProgrammeLibrary.shared.loadArtwork?.call(entry) ??
            Future<ImageProvider?>.value(null));
  bool watchlist = false;
  final controlsFocus = FocusNode(debugLabel: 'Programme filters');
  final firstCardFocus = FocusNode(debugLabel: 'First programme');
  final cardsScope = FocusScopeNode(debugLabel: 'Programme cards');
  @override
  void dispose() {
    cardsScope.dispose();
    controlsFocus.dispose();
    firstCardFocus.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    ProgrammeLibrary.shared.ready();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: ProgrammeLibrary.shared,
    builder: (_, __) {
      final library = ProgrammeLibrary.shared;
      final showingWatchlist = watchlist && library.saved.isNotEmpty;
      final base = showingWatchlist
          ? library.saved.values
                .where((e) => !library.hidden.contains(e.key))
                .toList()
          : library.visible;
      final providers = base.map((e) => e.provider).toSet().toList()..sort();
      final active = providers.contains(provider) ? provider : null;
      final entries = base
          .where(
            (e) =>
                library.sourceEnabled(e) &&
                (active == null || e.provider == active),
          )
          .toList();
      return Column(
        key: widget.spotlight ? programmeSpotlightShelfKey : null,
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (library.sourceError != null && entries.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(library.sourceError!),
            ),
          Focus(
            canRequestFocus: false,
            onFocusChange: (value) {
              if (!value) return;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                // The spotlight shelf scrolls into view as a whole, so the
                // large panel is never cut off.
                final target = widget.spotlight
                    ? context
                    : FocusManager.instance.primaryFocus?.context;
                if (target != null) {
                  Scrollable.ensureVisible(
                    target,
                    alignment: widget.spotlight ? .5 : .25,
                    duration: motionReduced(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                  );
                }
              });
            },
            onKeyEvent: (row, event) {
              if (event.logicalKey != LogicalKeyboardKey.arrowDown ||
                  entries.isEmpty)
                return RemoteFocusRow.handle(row, event);
              if (event is KeyDownEvent || event is KeyRepeatEvent)
                (cardsScope.focusedChild?.context != null
                        ? cardsScope.focusedChild
                        : cardsScope.traversalDescendants
                              .where(
                                (node) =>
                                    node.canRequestFocus &&
                                    node is! FocusScopeNode &&
                                    !node.descendants.any(
                                      (child) =>
                                          child.canRequestFocus &&
                                          child is! FocusScopeNode,
                                    ),
                              )
                              .firstOrNull)
                    ?.requestFocus();
              return KeyEventResult.handled;
            },
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        style: TextStyle(
                          fontSize: 23,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -.3,
                          color: MinimalPalette.of(context).text,
                        ),
                      ),
                      if (widget.caption != null)
                        Text(
                          widget.caption!,
                          style: TextStyle(
                            fontSize: 11,
                            color: MinimalPalette.of(context).muted,
                          ),
                        ),
                    ],
                  ),
                ),
                TextButton.icon(
                  key: const ValueKey('programme-filter-button'),
                  focusNode: controlsFocus,
                  onPressed: () => _filters(context),
                  icon: const Icon(Icons.tune_rounded, size: 18),
                  label: const Text('Options'),
                  style: TextButton.styleFrom(
                    foregroundColor: MinimalPalette.of(context).text,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                  ),
                ),
                if (active != null || showingWatchlist) ...[
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      [
                        if (showingWatchlist) 'Watchlist',
                        if (active != null) active,
                      ].join(' · '),
                      style: TextStyle(
                        fontSize: 13,
                        color: MinimalPalette.of(context).muted,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (entries.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    library.refreshing
                        ? 'Loading programmes...'
                        : library.sourceError != null
                        ? library.sourceError!
                        : !library.sourceAccessAllowed
                        ? 'Allow TV content access to see programmes.'
                        : active != null
                        ? 'No shared titles from $active. Try another source.'
                        : 'No programmes shared yet. Open a streaming app and start watching, then refresh.',
                  ),
                  if (library.refreshSources != null)
                    TextButton.icon(
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Refresh programmes'),
                      onPressed: () async {
                        try {
                          await library.refreshSources!();
                        } catch (_) {
                          if (context.mounted)
                            ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Could not refresh programmes. Try again.',
                                ),
                              ),
                            );
                        }
                      },
                    ),
                ],
              ),
            )
          else
            FocusScope(
              node: cardsScope,
              onKeyEvent: (_, event) {
                if (event.logicalKey != LogicalKeyboardKey.arrowUp)
                  return KeyEventResult.ignored;
                if (event is KeyDownEvent || event is KeyRepeatEvent)
                  controlsFocus.requestFocus();
                return KeyEventResult.handled;
              },
              child: widget.spotlight
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _Spotlight(
                          entry:
                              entries
                                  .where((e) => e.key == spotKey)
                                  .firstOrNull ??
                              entries.first,
                          artworkFor: artworkFor,
                        ),
                        const SizedBox(height: 14),
                        ProgrammeRail(
                          cardWidth: 208,
                          height: 150,
                          compact: true,
                          expandFocused: false,
                          itemCount: entries.length,
                          itemBuilder: (_, index) => Focus(
                            canRequestFocus: false,
                            skipTraversal: true,
                            onFocusChange: (focused) {
                              if (focused && spotKey != entries[index].key) {
                                setState(() => spotKey = entries[index].key);
                              }
                            },
                            child: LibraryProgrammeCard(
                              key: ValueKey(entries[index].key),
                              entry: entries[index],
                              compact: true,
                              focusNode: index == 0 ? firstCardFocus : null,
                            ),
                          ),
                        ),
                      ],
                    )
                  : ProgrammeRail(
                      cardWidth: 246,
                      height: 220,
                      compact: true,
                      itemCount: entries.length,
                      itemBuilder: (_, index) => LibraryProgrammeCard(
                        key: ValueKey(entries[index].key),
                        entry: entries[index],
                        compact: true,
                        focusNode: index == 0 ? firstCardFocus : null,
                      ),
                    ),
            ),
        ],
      );
    },
  );
  Future<void> _filters(BuildContext context) => showLumaDialog<void>(
    context: context,
    builder: (dialogContext) {
      final library = ProgrammeLibrary.shared;
      final source = watchlist && library.saved.isNotEmpty
          ? library.saved.values
          : library.visible;
      final names = source.map((e) => e.provider).toSet().toList()..sort();
      void choose(VoidCallback change) {
        setState(change);
        Navigator.pop(dialogContext);
      }

      return LumaMenuDialog(
        title: const Text('Programme options'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TvMenuRow(
              key: const ValueKey('programme-sources-button'),
              title: 'App sources',
              icon: Icons.apps_rounded,
              onPressed: () {
                Navigator.pop(dialogContext);
                showProgrammeSources(context);
              },
            ),
            TvMenuRow(
              title: 'From apps',
              autofocus: true,
              selected: !watchlist && provider == null,
              onPressed: () => choose(() {
                watchlist = false;
                provider = null;
              }),
            ),
            if (library.saved.isNotEmpty)
              TvMenuRow(
                title: 'Watchlist (${library.saved.length})',
                selected: watchlist,
                onPressed: () => choose(() {
                  watchlist = true;
                  provider = null;
                }),
              ),
            if (provider != null)
              TvMenuRow(
                title: 'All services',
                onPressed: () => choose(() => provider = null),
              ),
            for (final name in names)
              TvMenuRow(
                title: name,
                selected: provider == name,
                onPressed: () => choose(() => provider = name),
              ),
            if (library.hidden.isNotEmpty)
              TvMenuRow(
                title: 'Hidden titles',
                onPressed: () {
                  Navigator.pop(dialogContext);
                  _hidden(context);
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
      );
    },
  );

  Future<void> _hidden(BuildContext context) => showLumaDialog<void>(
    context: context,
    builder: (dialogContext) => ListenableBuilder(
      listenable: ProgrammeLibrary.shared,
      builder: (_, __) {
        final library = ProgrammeLibrary.shared;
        final known = {
          for (final e in [...library.source, ...library.saved.values])
            e.key: e,
        };
        return LumaMenuDialog(
          title: const Text('Hidden titles'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final key in library.hidden)
                TextButton(
                  onPressed: () => library.restoreHidden(key),
                  child: Text('Restore ${known[key]?.item.title ?? key}'),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Back'),
            ),
          ],
        );
      },
    ),
  );
}
