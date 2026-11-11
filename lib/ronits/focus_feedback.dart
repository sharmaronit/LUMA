import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'motion.dart';
import 'glass_surface.dart';

/// One moving indicator per surface, independent of artwork painting.
class FocusHighlightLayer extends StatefulWidget {
  const FocusHighlightLayer({
    super.key,
    required this.child,
    this.menu = false,
    this.cardFocus = false,
    this.frameAbove = false,
    this.reducedMotion = false,
  });
  final Widget child;
  final bool menu, cardFocus, reducedMotion, frameAbove;
  @override
  State<FocusHighlightLayer> createState() => _FocusHighlightLayerState();
}

class _FocusHighlightLayerState extends State<FocusHighlightLayer> {
  final _canvas = GlobalKey();
  GlobalKey? _target;
  Rect? _rect;
  bool _scrolling = false;
  Size? _layoutSize;
  @override
  void didUpdateWidget(FocusHighlightLayer old) {
    super.didUpdateWidget(old);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _measure(scrolling: true),
    );
  }

  void track(GlobalKey key, bool focused) {
    if (!focused) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _target == key) setState(() => _target = null);
      });
      return;
    }
    _target = key;
    _scrolling = false;
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _measure({bool scrolling = false}) {
    if (!mounted) return;
    final target = _target?.currentContext?.findRenderObject();
    final canvas = _canvas.currentContext?.findRenderObject();
    if (target is! RenderBox ||
        canvas is! RenderBox ||
        !target.attached ||
        !canvas.attached) {
      if (_target != null) setState(() => _target = null);
      return;
    }
    final origin = canvas.globalToLocal(target.localToGlobal(Offset.zero));
    final rect = origin & target.size;

    setState(() {
      _rect = rect;
      _scrolling = scrolling;
    });
  }

  @override
  Widget build(BuildContext context) {
    // App tiles own their lift; avoid geometry tracking and overlay painting.
    if (widget.cardFocus) return widget.child;
    final size = MediaQuery.sizeOf(context);
    if (_layoutSize != size) {
      _layoutSize = size;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _measure(scrolling: true),
      );
    }
    final source = _rect;
    final reduced = motionReduced(context, widget.reducedMotion);
    final rect = widget.cardFocus && source != null
        ? Rect.fromCenter(
            center: source.center,
            width: source.width * (reduced ? 1 : 1.07) + 4,
            height: source.height * (reduced ? 1 : 1.07) + 4,
          ).shift(Offset(0, reduced ? 0 : -6))
        : source;
    final current = ModalRoute.isCurrentOf(context) ?? true;
    final visible =
        current &&
        _target != null &&
        rect != null &&
        rect.bottom > 0 &&
        (!widget.frameAbove || rect.top >= 84);
    return _FocusFeedbackScope(
      track: track,
      child: NotificationListener<Notification>(
        onNotification: (event) {
          if (_target != null &&
              (event is ScrollNotification ||
                  event is LumaGeometryNotification))
            _measure(scrolling: true);
          return false;
        },
        child: Stack(
          key: _canvas,
          clipBehavior: widget.cardFocus ? Clip.hardEdge : Clip.none,
          children: [
            if (widget.frameAbove) widget.child,
            if (!widget.cardFocus && widget.menu && visible)
              AnimatedPositioned(
                duration: motionReduced(context) || _scrolling
                    ? Duration.zero
                    : const Duration(milliseconds: 240),
                curve: lumaEase,
                left: rect.left,
                top: rect.top,
                width: rect.width,
                height: rect.height,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color:
                          (MenuAppearanceScope.of(context)?.mode ==
                                      LauncherMaterial.minimal
                                  ? MinimalPalette.of(context).accent
                                  : Colors.white)
                              .withValues(alpha: .16),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color:
                            (MenuAppearanceScope.of(context)?.mode ==
                                        LauncherMaterial.minimal
                                    ? MinimalPalette.of(context).accent
                                    : Colors.white)
                                .withValues(alpha: .28),
                        width: 1,
                      ),
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            if (!widget.frameAbove) widget.child,
            if (!widget.cardFocus && !widget.menu && visible)
              AnimatedPositioned(
                duration: motionReduced(context) || _scrolling
                    ? Duration.zero
                    : const Duration(milliseconds: 240),
                curve: lumaEase,
                left: rect.left + rect.width * .22,
                top: rect.bottom + 8,
                width: rect.width * .56,
                height: 3,
                child: IgnorePointer(
                  child: DecoratedBox(
                    key: const ValueKey('app-focus-underline'),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(3),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x55000000),
                          blurRadius: 4,
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _FocusFeedbackScope extends InheritedWidget {
  const _FocusFeedbackScope({required this.track, required super.child});
  final void Function(GlobalKey key, bool focused) track;
  @override
  bool updateShouldNotify(_FocusFeedbackScope old) => false;
}

void reportFocusTarget(BuildContext context, GlobalKey key, bool focused) =>
    context.getInheritedWidgetOfExactType<_FocusFeedbackScope>()?.track(
      key,
      focused,
    );

class TvMenuRow extends StatefulWidget {
  const TvMenuRow({
    super.key,
    required this.title,
    required this.onPressed,
    this.subtitle,
    this.icon,
    this.trailing,
    this.autofocus = false,
    this.selected = false,
    this.focusNode,
  });
  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget? trailing;
  final VoidCallback onPressed;
  final bool autofocus, selected;
  final FocusNode? focusNode;
  @override
  State<TvMenuRow> createState() => _TvMenuRowState();
}

class _TvMenuRowState extends State<TvMenuRow> {
  final _ownedFocus = FocusNode();
  FocusNode get _focus => widget.focusNode ?? _ownedFocus;
  final _target = GlobalKey();
  bool focused = false, pressed = false;
  @override
  void dispose() {
    _ownedFocus.dispose();
    super.dispose();
  }

  void _changed(bool value) {
    setState(() {
      focused = value;
      if (!value) pressed = false;
    });
    if (value)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_focus.hasFocus) return;
        final target = context.findRenderObject();
        if (target != null) {
          revealScrollFocus(context, target, reduced: motionReduced(context));
        }
      });
  }

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: widget.selected,
    label: widget.title,
    child: Focus(
      focusNode: _focus,
      autofocus: widget.autofocus,
      onFocusChange: _changed,
      onKeyEvent: (_, event) {
        if (![
          LogicalKeyboardKey.enter,
          LogicalKeyboardKey.numpadEnter,
          LogicalKeyboardKey.select,
          LogicalKeyboardKey.space,
          LogicalKeyboardKey.gameButtonA,
        ].contains(event.logicalKey))
          return KeyEventResult.ignored;
        if (event is KeyDownEvent) setState(() => pressed = true);
        if (event is KeyUpEvent && pressed) {
          setState(() => pressed = false);
          widget.onPressed();
        }
        return KeyEventResult.handled;
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onHover: (_) {
          if (!_focus.hasFocus) _focus.requestFocus();
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) {
            _focus.requestFocus();
            setState(() => pressed = true);
          },
          onTapCancel: () => setState(() => pressed = false),
          onTapUp: (_) => setState(() => pressed = false),
          onTap: widget.onPressed,
          child: AnimatedScale(
            scale: pressed ? .98 : 1,
            duration: motionReduced(context)
                ? Duration.zero
                : const Duration(milliseconds: 100),
            child: AnimatedContainer(
              key: const ValueKey('menu-row-focus-tint'),
              duration: !focused || motionReduced(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 120),
              clipBehavior: Clip.hardEdge,
              decoration: BoxDecoration(
                color: focused
                    ? _menuText(context).withValues(alpha: .16)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: focused
                      ? _menuText(context).withValues(alpha: .28)
                      : Colors.transparent,
                ),
              ),
              child: Padding(
                key: _target,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    if (widget.icon != null) ...[
                      GlassIconChip(icon: widget.icon!, focused: focused),
                      const SizedBox(width: 16),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.title,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: focused || widget.selected
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              color: _menuText(context),
                            ),
                          ),
                          if (widget.subtitle != null) ...[
                            const SizedBox(height: 3),
                            Text(
                              widget.subtitle!,
                              style: TextStyle(
                                fontSize: 12,
                                color: _menuMuted(context),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    widget.trailing ??
                        Icon(
                          widget.selected
                              ? Icons.check_rounded
                              : Icons.chevron_right,
                          size: 20,
                          color: _menuMuted(context),
                        ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

Color _menuText(BuildContext context) =>
    MenuAppearanceScope.of(context)?.mode == LauncherMaterial.minimal
    ? MinimalPalette.of(context).text
    : Colors.white;
Color _menuMuted(BuildContext context) =>
    MenuAppearanceScope.of(context)?.mode == LauncherMaterial.minimal
    ? MinimalPalette.of(context).muted
    : Colors.white70;


/// A small rounded square of frosted glass holding a menu icon. Monochrome:
/// white glyph on clear glass, inverting to a dark glyph on white when its
/// row is focused.
class GlassIconChip extends StatelessWidget {
  const GlassIconChip({
    super.key,
    required this.icon,
    this.focused = false,
    this.size = 36,
  });
  final IconData icon;
  final bool focused;
  final double size;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(size * .3);
    return SizedBox.square(
      key: const ValueKey('glass-icon-chip'),
      dimension: size,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: focused
                ? const [Color(0xfff4f5f7), Color(0xffdfe2e7)]
                : [
                    Colors.white.withValues(alpha: .16),
                    Colors.white.withValues(alpha: .07),
                  ],
          ),
          shape: RoundedSuperellipseBorder(
            borderRadius: radius,
            side: BorderSide(
              color: Colors.white.withValues(alpha: focused ? .9 : .20),
              width: .8,
            ),
          ),
        ),
        child: Icon(
          icon,
          size: size * .54,
          color: focused ? const Color(0xff111316) : Colors.white,
        ),
      ),
    );
  }
}
