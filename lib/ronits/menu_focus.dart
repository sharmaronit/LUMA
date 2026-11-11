import 'package:flutter/material.dart';
import 'motion.dart' show motionReduced, revealScrollFocus;

int _revision = 0;
int get menuFocusRevision => _revision;
void cancelPendingMenuFocusRestores() => _revision++;

void restoreMenuFocus(
  FocusNode? target,
  Route<dynamic>? parent, {
  int? revision,
}) {
  if (revision != null && revision != _revision) return;
  final context = target?.context;
  if (context == null ||
      !context.mounted ||
      !target!.canRequestFocus ||
      (parent != null && !parent.isCurrent))
    return;
  target.requestFocus();
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final current = target.context;
    if (current == null || !current.mounted || !target.hasFocus) return;
    final targetBox = current.findRenderObject();
    if (targetBox != null) {
      revealScrollFocus(current, targetBox, reduced: motionReduced(current));
    }
  });
}

/// Retains the launching control for nested native settings routes.
class MenuFocusObserver extends NavigatorObserver {
  final _targets = <Route<dynamic>, (FocusNode?, int)>{};
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute != null)
      _targets[previousRoute] = (
        FocusManager.instance.primaryFocus,
        menuFocusRevision,
      );
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _targets.remove(route);
    final target = _targets.remove(previousRoute);
    if (route is TransitionRoute) {
      route.completed.then(
        (_) =>
            restoreMenuFocus(target?.$1, previousRoute, revision: target?.$2),
      );
    } else {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) =>
            restoreMenuFocus(target?.$1, previousRoute, revision: target?.$2),
      );
    }
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _targets.remove(route);
}
