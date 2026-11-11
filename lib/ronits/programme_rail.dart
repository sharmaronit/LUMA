import 'dart:async';
import 'cinematic_backdrop.dart';
import 'remote_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'glass_surface.dart';
import 'motion.dart';
import 'programme_source_icon.dart';
import 'scroll_edge_fade.dart';

/// Marks a Home shelf whose cards should scroll the whole shelf into view.
const programmeSpotlightShelfKey = ValueKey('programme-spotlight-shelf');

/// Shared TV/browser presentation. Provider access stays outside this widget.
class ProgrammeRail extends StatefulWidget {
  const ProgrammeRail({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.height = 210,
    this.cardWidth = 292,
    this.compact = false,
    this.expandFocused,
  });
  final bool compact;
  final double height, cardWidth;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  /// Compact rails widen the focused card (same height, wider artwork) and
  /// move its title, app and progress onto the artwork. Defaults to [compact].
  final bool? expandFocused;

  /// How much wider the focused card grows, as a share of [cardWidth].
  static const expansion = .6;

  @override
  State<ProgrammeRail> createState() => _ProgrammeRailState();
}

class _ProgrammeRailState extends State<ProgrammeRail> {
  int? focusedIndex;

  bool get _expands => widget.expandFocused ?? widget.compact;

  @override
  Widget build(BuildContext context) {
    final compact = widget.compact;
    final cardWidth = widget.cardWidth;
    final reduced = motionReduced(context);
    return SizedBox(
      height:
          widget.height.clamp(
            cardWidth * 9 / 16 * 1.03 + (compact ? 92 : 38),
            double.infinity,
          ) +
          (MediaQuery.textScalerOf(context).scale(14) - 14) * 4,
      child: RemoteFocusRow(
        child: ScrollEdgeFade(
          axis: Axis.horizontal,
          extent: 28,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final slotWidth = cardWidth + (compact ? 16 : 40);
              return ListView.separated(
                key: const PageStorageKey('programme-rail'),
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.fromLTRB(0, compact ? 12 : 22, 0, 16),
                itemCount: widget.itemCount,
                separatorBuilder: (_, __) => const SizedBox(width: 20),
                itemBuilder: (context, index) {
                  final child = widget.itemBuilder(context, index);
                  if (!_expands) {
                    return SizedBox(width: slotWidth, child: child);
                  }
                  return Focus(
                    canRequestFocus: false,
                    skipTraversal: true,
                    onFocusChange: (value) {
                      if (value && focusedIndex != index) {
                        setState(() => focusedIndex = index);
                      } else if (!value && focusedIndex == index) {
                        setState(() => focusedIndex = null);
                      }
                    },
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(end: focusedIndex == index ? 1 : 0),
                      duration: reduced ? Duration.zero : lumaFocusDuration,
                      curve: lumaFocusCurve,
                      onEnd: () {
                        // Once wide, bring the whole card into view.
                        if (focusedIndex != index || !mounted) return;
                        final focus = FocusManager.instance.primaryFocus;
                        final render = focus?.context?.findRenderObject();
                        if (render != null && focus!.context!.mounted) {
                          revealHorizontalFocus(
                            focus.context!,
                            render,
                            reduced: reduced,
                          );
                        }
                      },
                      child: child,
                      builder: (_, t, child) => SizedBox(
                        width:
                            slotWidth + cardWidth * ProgrammeRail.expansion * t,
                        child: ProgrammeRailSlot(
                          expansion: t,
                          cardWidth: cardWidth,
                          child: child!,
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Tells a compact card how far its slot has widened (0 = normal, 1 = wide).
class ProgrammeRailSlot extends InheritedWidget {
  const ProgrammeRailSlot({
    super.key,
    required this.expansion,
    required this.cardWidth,
    required super.child,
  });
  final double expansion, cardWidth;

  static ProgrammeRailSlot? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ProgrammeRailSlot>();

  /// Artwork aspect ratio that keeps the card's height fixed as it widens.
  double get aspectRatio =>
      (cardWidth + cardWidth * ProgrammeRail.expansion * expansion) /
      (cardWidth * 9 / 16);

  @override
  bool updateShouldNotify(ProgrammeRailSlot oldWidget) =>
      expansion != oldWidget.expansion || cardWidth != oldWidget.cardWidth;
}

class ProgrammeCard extends StatefulWidget {
  const ProgrammeCard({
    super.key,
    required this.title,
    this.subtitle,
    this.provider,
    this.providerId,
    this.footer,
    this.progress,
    this.artwork,
    this.loading = false,
    required this.onPressed,
    this.onOptions,
    this.focusNode,
    this.compact = false,
  });
  final bool compact;
  final String title;
  final String? subtitle, footer, provider;
  final String? providerId;
  final double? progress;
  final ImageProvider? artwork;
  final bool loading;
  final VoidCallback onPressed;
  final VoidCallback? onOptions;
  final FocusNode? focusNode;
  @override
  State<ProgrammeCard> createState() => _ProgrammeCardState();
}

class _ProgrammeCardState extends State<ProgrammeCard> {
  final _ownedFocus = FocusNode();
  FocusNode get focus => widget.focusNode ?? _ownedFocus;
  bool focused = false;
  DateTime? lastPressed;
  Timer? hold;
  bool held = false, longPress = false;
  @override
  void didUpdateWidget(ProgrammeCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (focused && oldWidget.artwork != widget.artwork) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && focus.hasFocus)
          ProgrammeArtworkFocus(
            widget.compact ? null : widget.artwork,
          ).dispatch(context);
      });
    }
  }

  @override
  void dispose() {
    hold?.cancel();
    _ownedFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = MinimalPalette.of(context);
    final reduced = motionReduced(context);
    final carousel =
        context.findAncestorWidgetOfExactType<ProgrammeRail>() != null;
    final seed = (widget.providerId ?? widget.provider ?? widget.title)
        .codeUnits
        .fold<int>(0, (value, unit) => (value * 31 + unit) & 0xffff);
    final placeholder = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            HSLColor.fromAHSL(1, (seed % 360).toDouble(), .3, .26).toColor(),
            const Color(0xff101923),
          ],
        ),
      ),
      child: Center(
        child: Icon(
          widget.loading ? Icons.image_outlined : Icons.movie_outlined,
          semanticLabel: widget.loading
              ? 'Loading artwork'
              : 'Artwork unavailable',
          size: 44,
          color: Colors.white.withValues(alpha: .18),
        ),
      ),
    );
    final picture = RepaintBoundary(
      child: widget.artwork == null
          ? placeholder
          : Image(
              image: ResizeImage(
                widget.artwork!,
                width: widget.compact ? 640 : 960,
                allowUpscaling: false,
                policy: ResizeImagePolicy.fit,
              ),
              filterQuality: FilterQuality.medium,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => placeholder,
            ),
    );
    final card = TextButton(
      focusNode: focus,
      onLongPress: widget.onOptions,
      onPressed: () {
        final now = DateTime.now();
        if (lastPressed != null &&
            now.difference(lastPressed!).inMilliseconds < 400)
          return;
        lastPressed = now;
        widget.onPressed();
      },
      clipBehavior: widget.compact ? Clip.none : Clip.hardEdge,
      style: ButtonStyle(
        alignment: Alignment.center,
        animationDuration: Duration.zero,
        splashFactory: NoSplash.splashFactory,
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        backgroundColor: WidgetStatePropertyAll(
          widget.compact ? Colors.transparent : palette.surface,
        ),
        foregroundColor: const WidgetStatePropertyAll(Colors.white),
        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
        shape: WidgetStatePropertyAll(
          RoundedSuperellipseBorder(
            borderRadius: BorderRadius.circular(lumaCardRadius),
          ),
        ),
      ),
      child: widget.compact
          ? _compactContent(picture)
          : Stack(
              fit: StackFit.expand,
              children: [
                picture,
                const Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      key: ValueKey('programme-artwork-gradient'),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          stops: [0, .48, 1],
                          colors: [
                            Color(0x08000000),
                            Color(0x00000000),
                            Color(0xee05090f),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                if (widget.provider?.isNotEmpty ?? false)
                  Positioned(
                    top: 10,
                    left: 10,
                    right: 40,
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: const Color(0x990b111b),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 4,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ProgrammeSourceIcon(
                                source: widget.providerId ?? widget.provider!,
                                name: widget.provider!,
                              ),
                              const SizedBox(width: 7),
                              Flexible(
                                child: Text(
                                  widget.provider!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  left: 14,
                  right: 14,
                  bottom: widget.progress == null ? 14 : 19,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          letterSpacing: .15,
                          color: Colors.white,
                        ),
                      ),
                      if (widget.subtitle?.isNotEmpty ?? false) ...[
                        const SizedBox(height: 4),
                        Text(
                          widget.subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xffd9dfe7),
                          ),
                        ),
                      ],
                      if (widget.footer?.isNotEmpty ?? false) ...[
                        const SizedBox(height: 4),
                        Text(
                          widget.footer!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 10,
                            color: Color(0xffc1cad7),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (widget.progress != null &&
                    widget.progress! > 0 &&
                    widget.progress! < 1)
                  Positioned(
                    left: 14,
                    right: 14,
                    bottom: 9,
                    child: LinearProgressIndicator(
                      value: widget.progress!.clamp(0, 1),
                      minHeight: 2,
                      color: Colors.white,
                      backgroundColor: Colors.white24,
                      semanticsLabel: '${widget.title} watch progress',
                      semanticsValue: '${(widget.progress! * 100).round()}',
                    ),
                  ),
              ],
            ),
    );
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: widget.compact
            ? 8
            : carousel
            ? 20
            : 12,
      ),
      child: Focus(
        canRequestFocus: false,
        onKeyEvent: (_, event) {
          if (widget.onOptions == null) return KeyEventResult.ignored;
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.contextMenu && event is KeyDownEvent) {
            widget.onOptions!();
            return KeyEventResult.handled;
          }
          if (![
            LogicalKeyboardKey.enter,
            LogicalKeyboardKey.select,
            LogicalKeyboardKey.space,
            LogicalKeyboardKey.gameButtonA,
          ].contains(key))
            return KeyEventResult.ignored;
          if (event is KeyDownEvent) {
            held = true;
            longPress = false;
            hold?.cancel();
            hold = Timer(const Duration(milliseconds: 600), () {
              if (held) longPress = true;
            });
          } else if (event is KeyUpEvent && held) {
            held = false;
            hold?.cancel();
            if (longPress) {
              widget.onOptions!();
            } else {
              widget.onPressed();
            }
          }
          return KeyEventResult.handled;
        },
        onFocusChange: (value) {
          setState(() => focused = value);
          // Focus notifications for the old and new cards can arrive in either
          // order. Read the final primary focus after both have been updated.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            final card = FocusManager.instance.primaryFocus?.context
                ?.findAncestorWidgetOfExactType<ProgrammeCard>();
            ProgrammeArtworkFocus(
              card?.compact == true ? null : card?.artwork,
            ).dispatch(context);
          });
          if (!value) {
            held = false;
            hold?.cancel();
          }
          if (value)
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && focus.hasFocus) {
                final render = context.findRenderObject();
                if (render == null) return;
                revealHorizontalFocus(context, render, reduced: reduced);
                // Reveal the rail in the outer viewport. Passing a card inside
                // a horizontal viewport to the vertical position computes the
                // offset in the wrong viewport and can jump Home back to zero.
                // A spotlight shelf is revealed as a whole, so its large
                // panel above the cards is never cut off.
                BuildContext? rail, shelf;
                context.visitAncestorElements((element) {
                  if (element.widget is ProgrammeRail) rail ??= element;
                  if (element.widget.key == programmeSpotlightShelfKey) {
                    shelf = element;
                    return false;
                  }
                  return true;
                });
                rail = shelf ?? rail;
                Scrollable.maybeOf(
                  context,
                  axis: Axis.vertical,
                )?.position.ensureVisible(
                  rail?.findRenderObject() ?? render,
                  alignment: .5,
                  alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
                  duration: reduced ? Duration.zero : lumaScrollDuration,
                  curve: lumaFocusCurve,
                );
              }
            });
        },
        child: MouseRegion(
          onEnter: (_) => focus.requestFocus(),
          child: Align(
            alignment: Alignment.topLeft,
            child: _cardExtent(
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: focused ? 1 : 0),
                duration: reduced ? Duration.zero : lumaFocusDuration,
                curve: lumaFocusCurve,
                child: RepaintBoundary(child: card),
                builder: (_, value, child) => Transform.translate(
                  offset: Offset(
                    0,
                    reduced ? 0 : -(widget.compact ? 2 : 6) * value,
                  ),
                  child: Transform.scale(
                    scale: reduced
                        ? 1
                        : 1 + (widget.compact ? .025 : .05) * value,
                    child: DecoratedBox(
                      position: DecorationPosition.foreground,
                      decoration: ShapeDecoration(
                        shape: RoundedSuperellipseBorder(
                          borderRadius: BorderRadius.circular(lumaCardRadius),
                          side: BorderSide(
                            color: Colors.white.withValues(
                              alpha: widget.compact ? 0 : .9 * value,
                            ),
                            width: 1.5,
                          ),
                        ),
                      ),
                      child: child,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _cardExtent({required Widget child}) => widget.compact
      ? SizedBox(width: double.infinity, child: child)
      : AspectRatio(aspectRatio: 16 / 9, child: child);

  Widget _compactContent(Widget picture) {
    final slot = ProgrammeRailSlot.of(context);
    final t = slot?.expansion ?? 0;
    final progress =
        widget.progress != null && widget.progress! > 0 && widget.progress! < 1
        ? widget.progress!
        : null;
    // The wide card carries its details on the artwork instead of below it.
    final wide = t > .5;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AspectRatio(
          aspectRatio: slot?.aspectRatio ?? 16 / 9,
          child: _compactArtwork(picture, t, progress),
        ),
        if (!wide) ..._compactDetails(),
      ],
    );
  }

  Widget _compactArtwork(Widget picture, double t, double? progress) =>
      DecoratedBox(
        key: const ValueKey('compact-programme-artwork'),
        position: DecorationPosition.foreground,
        decoration: ShapeDecoration(
          shape: RoundedSuperellipseBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: focused ? Colors.white : Colors.transparent,
              width: 1,
            ),
          ),
        ),
        child: ClipRSuperellipse(
          borderRadius: BorderRadius.circular(14),
          child: Stack(
            fit: StackFit.expand,
            children: [
              picture,
              if (t > 0)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Opacity(opacity: t, child: _wideDetails(progress)),
                  ),
                ),
              if (progress != null && t < 1)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Opacity(
                    opacity: 1 - t,
                    child: LinearProgressIndicator(
                      value: progress.clamp(0, 1),
                      minHeight: 2,
                      color: Colors.white,
                      backgroundColor: Colors.black45,
                      semanticsLabel: '${widget.title} watch progress',
                      semanticsValue: '${(progress * 100).round()}',
                    ),
                  ),
                ),
            ],
          ),
        ),
      );

  /// Title, app and progress laid over the widened card's artwork.
  Widget _wideDetails(double? progress) => DecoratedBox(
    key: const ValueKey('programme-wide-details'),
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        stops: [.25, 1],
        colors: [Color(0x00000000), Color(0xe6050810)],
      ),
    ),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          if (widget.provider?.isNotEmpty ?? false) ...[
            const SizedBox(height: 5),
            Row(
              children: [
                SizedBox(
                  width: 22,
                  height: 14,
                  child: ProgrammeSourceIcon(
                    source: widget.providerId ?? widget.provider!,
                    name: widget.provider!,
                  ),
                ),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    [
                      widget.provider!,
                      if (widget.subtitle?.isNotEmpty ?? false)
                        widget.subtitle!,
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xffdfe5ec),
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (progress != null) ...[
            const SizedBox(height: 9),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: progress.clamp(0, 1),
                minHeight: 3,
                color: Colors.white,
                backgroundColor: Colors.white24,
              ),
            ),
          ],
        ],
      ),
    ),
  );

  List<Widget> _compactDetails() => [
    const SizedBox(height: 9),
    Text(
      widget.title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: Colors.white,
      ),
    ),
    if (widget.provider?.isNotEmpty ?? false) ...[
      const SizedBox(height: 4),
      Row(
        children: [
          SizedBox(
            width: 22,
            height: 14,
            child: ProgrammeSourceIcon(
              source: widget.providerId ?? widget.provider!,
              name: widget.provider!,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              widget.provider!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: Color(0xffcbd3dd)),
            ),
          ),
        ],
      ),
    ],
    if (widget.subtitle?.isNotEmpty ?? false)
      Text(
        widget.subtitle!,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 11, color: Color(0xffcbd3dd)),
      ),
  ];
}
