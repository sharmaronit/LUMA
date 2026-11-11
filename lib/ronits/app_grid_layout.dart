import 'package:flutter/widgets.dart';

/// Sparse libraries use fewer columns; larger libraries keep the user's setting.
int adaptiveAppColumns({
  required Size viewport,
  required int appCount,
  required int preferredColumns,
  required double dockExtent,
  required double labelExtent,
  bool matchingDock = false,
}) {
  final preferred = preferredColumns.clamp(3, 8);
  if (appCount == 0 || appCount > preferred * 2) return preferred;
  var best = preferred;
  var bestScore = double.infinity;
  for (var columns = preferred >= 4 ? 4 : 3; columns <= preferred; columns++) {
    final width = ((viewport.width - 120 - 20 * (columns - 1)) / columns).clamp(
      56.0,
      double.infinity,
    );
    final tileHeight = (width - 8) * 9 / 16 + 14 + labelExtent;
    final rows = (appCount / columns).ceil();
    final used =
        (matchingDock && dockExtent > 0 ? tileHeight + 36 : dockExtent) +
        24 +
        rows * tileHeight +
        (rows - 1) * 24 +
        40;
    final difference = used - viewport.height;
    final incomplete = appCount % columns;
    final emptyCells = incomplete == 0 ? 0 : (columns - incomplete) / columns;
    final score =
        difference.abs() * (difference > 0 ? 1.2 : 1) +
        viewport.height * .20 * emptyCells;
    if (score < bestScore) {
      best = columns;
      bestScore = score;
    }
  }
  return best;
}
