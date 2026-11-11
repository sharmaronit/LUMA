import '../../models/app.dart';
import '../../models/category.dart';
import '../../providers/apps_service.dart';
import '../../ronits/menu_undo.dart';

Future<MenuUndo?> toggleFavoriteWithUndo(AppsService service, App app) async {
  final removing = service.isAppInFavorites(app);
  final category = removing
      ? await service.getOrCreateFavoritesCategory()
      : null;
  final index =
      category?.applications.indexWhere(
        (entry) => entry.packageName == app.packageName,
      ) ??
      -1;
  await service.toggleFavorite(app);
  if (!removing) return null;
  return MenuUndo('Removed ${app.name} from dock', () async {
    if (!service.isAppInFavorites(app)) await service.addToFavorites(app);
    final favorites = await service.getOrCreateFavoritesCategory();
    final current = favorites.applications.indexWhere(
      (entry) => entry.packageName == app.packageName,
    );
    if (current >= 0 && index >= 0 && current != index) {
      await service.reorderApplication(
        favorites,
        current,
        index.clamp(0, favorites.applications.length - 1),
      );
    }
  });
}

Future<MenuUndo?> toggleHiddenWithUndo(AppsService service, App app) async {
  if (app.hidden) {
    await service.showApplication(app);
    return null;
  }
  await service.hideApplication(app);
  return MenuUndo('Hidden ${app.name}', () => service.showApplication(app));
}

Future<MenuUndo> removeCategoryAppWithUndo(
  AppsService service,
  App app,
  Category category,
) async {
  final index = category.applications.indexWhere(
    (entry) => entry.packageName == app.packageName,
  );
  await service.removeFromCategory(app, category);
  return MenuUndo('Removed ${app.name} from ${category.name}', () async {
    await service.addToCategory(app, category);
    final current = category.applications.indexWhere(
      (entry) => entry.packageName == app.packageName,
    );
    if (category.sort == CategorySort.manual &&
        current >= 0 &&
        index >= 0 &&
        current != index) {
      await service.reorderApplication(
        category,
        current,
        index.clamp(0, category.applications.length - 1),
      );
    }
  });
}
