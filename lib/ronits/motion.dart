import 'menu_focus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/gestures.dart' show Drag;

class LumaGeometryNotification extends Notification {
  const LumaGeometryNotification();
}

const lumaEase = Cubic(.16, 1, .3, 1);
const lumaCardRadius = 22.0;
const lumaPanelRadius = 28.0;
const lumaFocusDuration = Duration(milliseconds: 160);
const lumaFocusCurve = Curves.easeOutCubic;
const lumaScrollDuration = Duration(milliseconds: 220);

bool motionReduced(BuildContext context, [bool preference = false]) =>
    preference || MediaQuery.disableAnimationsOf(context);

/// Translate a cached menu surface; no animated opacity, scale or image filter.
class MenuSlideTransition extends StatelessWidget {
  const MenuSlideTransition({
    super.key,
    required this.animation,
    required this.child,
    this.begin = const Offset(0, 14),
  });
  final Animation<double> animation;
  final Widget child;
  final Offset begin;
  @override
  Widget build(BuildContext context) {
    if (motionReduced(context)) return child;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (_, page) {
        final delta =
            begin * (1 - Curves.easeOutCubic.transform(animation.value));
        return Transform.translate(
          key: const ValueKey('menu-slide-transform'),
          // One position curve stays continuous if Back interrupts opening.
          offset: Offset(
            (delta.dx * dpr).round() / dpr,
            (delta.dy * dpr).round() / dpr,
          ),
          child: page,
        );
      },
    );
  }
}

Future<T?> showLumaDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool reducedMotion = false,
  bool fromSide = false,
  bool barrierDismissible = true,
  bool floating = false,
  bool fromTop = false,
}) {
  final revision = menuFocusRevision;
  final target = FocusManager.instance.primaryFocus;
  final parent = target?.context == null
      ? ModalRoute.of(context)
      : ModalRoute.of(target!.context!);
  final route = RawDialogRoute<T>(
    barrierDismissible: barrierDismissible,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.transparent,
    transitionDuration: motionReduced(context, reducedMotion)
        ? Duration.zero
        : const Duration(milliseconds: 140),
    pageBuilder: (context, _, _) => SafeArea(child: builder(context)),
    transitionBuilder: (context, animation, secondary, page) =>
        MenuSlideTransition(
          animation: animation,
          begin: fromSide
              ? const Offset(24, 0)
              : fromTop
              ? const Offset(0, -20)
              : floating
              ? const Offset(0, 8)
              : const Offset(0, 14),
          child: page,
        ),
  );
  route.completed.then(
    (_) => restoreMenuFocus(target, parent, revision: revision),
  );
  return Navigator.of(context, rootNavigator: true).push<T>(route);
}

/// Finite entrance animation: no repeating animation or per-tile controllers.
class LumaEntrance extends StatelessWidget {
  const LumaEntrance({
    super.key,
    required this.child,
    this.reducedMotion = false,
  });
  final Widget child;
  final bool reducedMotion;
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: motionReduced(context, reducedMotion)
        ? Duration.zero
        : const Duration(milliseconds: 520),
    curve: lumaEase,
    child: child,
    // A transform-only entrance avoids a grid-sized opacity layer.
    builder: (_, value, child) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) const LumaGeometryNotification().dispatch(context);
      });
      return Transform.translate(
        offset: Offset(0, 14 * (1 - value)),
        child: child,
      );
    },
  );
}

/// Wheel input eases to its destination; touch retains Flutter's native physics.
class LumaScrollController extends ScrollController {
  bool reducedMotion = false;
  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) => _LumaScrollPosition(
    physics: physics,
    context: context,
    oldPosition: oldPosition,
    reduce: () => reducedMotion,
  );
}

class _LumaScrollPosition extends ScrollPositionWithSingleContext {
  _LumaScrollPosition({
    required super.physics,
    required super.context,
    super.oldPosition,
    required this.reduce,
  });
  final bool Function() reduce;
  double? _target;
  bool _wheelAnimating = false;
  @override
  Drag drag(DragStartDetails details, VoidCallback cancel) {
    _target = null;
    _wheelAnimating = false;
    return super.drag(details, cancel);
  }

  @override
  Future<void> animateTo(
    double to, {
    required Duration duration,
    required Curve curve,
  }) {
    if (!_wheelAnimating) _target = null;
    return super.animateTo(to, duration: duration, curve: curve);
  }

  @override
  void pointerScroll(double delta) {
    if (reduce()) {
      super.pointerScroll(delta);
      return;
    }
    if (delta == 0) return;
    final target = ((_target ?? pixels) + delta)
        .clamp(minScrollExtent, maxScrollExtent)
        .toDouble();
    _target = target;
    _wheelAnimating = true;
    final motion = super.animateTo(
      target,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
    );
    _wheelAnimating = false;
    motion.whenComplete(() {
      if (_target == target) _target = null;
    });
  }
}

/// Keep the row still while focus remains visible; reveal either edge equally.
void revealHorizontalFocus(
  BuildContext context,
  RenderObject target, {
  required bool reduced,
}) =>
    revealScrollFocus(context, target, reduced: reduced, axis: Axis.horizontal);

/// Reveal the nearest clipped edge in either direction without centring.
void revealScrollFocus(
  BuildContext context,
  RenderObject target, {
  required bool reduced,
  Axis? axis,
}) {
  final position = Scrollable.maybeOf(context, axis: axis)?.position;
  if (position == null) return;
  final viewport = RenderAbstractViewport.of(target);
  final leading = viewport.getOffsetToReveal(target, 0).offset;
  final trailing = viewport.getOffsetToReveal(target, 1).offset;
  final offset = position.pixels > leading
      ? leading
      : position.pixels < trailing
      ? trailing
      : position.pixels;
  var destination = offset.clamp(
    position.minScrollExtent,
    position.maxScrollExtent,
  );
  // Revealing the first or last item goes all the way to the end of the
  // list. Stopping at the item's own edge left the list's padding scrolled
  // away, which let a sliver of the next off-screen item show at the far
  // side.
  const edge = 24.0;
  if (destination < position.pixels &&
      destination - position.minScrollExtent < edge) {
    destination = position.minScrollExtent;
  } else if (destination > position.pixels &&
      position.maxScrollExtent - destination < edge) {
    destination = position.maxScrollExtent;
  }
  if ((destination - position.pixels).abs() < .5) return;
  if (reduced) {
    position.jumpTo(destination);
    return;
  }
  position.animateTo(
    destination,
    duration: lumaScrollDuration,
    curve: lumaFocusCurve,
  );
}
