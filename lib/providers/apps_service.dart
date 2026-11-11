/*
 * FLauncher
 * Copyright (C) 2021  Étienne Fesser
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

import 'dart:async';
import 'dart:io';
import 'dart:collection';
import 'package:collection/collection.dart' as collection;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:drift/drift.dart';
import 'package:luma/database.dart';
import 'package:luma/luma_channel.dart';
import 'package:flutter/foundation.dart' hide Category;
import 'package:flutter/widgets.dart';

import '../models/app.dart';
import '../models/category.dart';

class AppsService extends ChangeNotifier {
  final LumaChannel _lumaChannel;
  final LumaDatabase _database;

  bool _initialized = false;
  bool _disposed = false;
  bool _initializing = false;
  Object? _initializationError;
  Object? get initializationError => _initializationError;
  Future<void> _eventQueue = Future.value();
  int _layoutVersion = 0;

  List<LauncherSection> _launcherSections = List.empty(growable: true);
  Map<String, App> _applications = Map();
  Map<String, Uint8List> _iconCache = Map();
  Map<String, Uint8List> _bannerCache = Map();
  final _bannerTasks = <String, Future<Uint8List>>{};
  final _iconTasks = <String, Future<Uint8List>>{};
  final _artworkVersions = <String, int>{};

  void _invalidateArtwork(String packageName) {
    _artworkVersions[packageName] = (_artworkVersions[packageName] ?? 0) + 1;
    _iconCache.remove(packageName);
    _bannerCache.remove(packageName);
    _iconTasks.remove(packageName);
    _bannerTasks.remove(packageName);
    _dirtyImagePackages.add(packageName);
  }

  Future<Uint8List> _loadArtwork(
    String packageName,
    Map<String, Uint8List> cache,
    Map<String, Future<Uint8List>> tasks,
    Future<Uint8List> Function(String) read,
  ) {
    final cached = cache[packageName];
    if (cached != null) return Future.value(cached);
    return tasks.putIfAbsent(packageName, () {
      final version = _artworkVersions[packageName];
      late final Future<Uint8List> task;
      task = read(packageName)
          .then((bytes) {
            if (!_disposed && _artworkVersions[packageName] == version)
              cache[packageName] = bytes;
            return bytes;
          })
          .whenComplete(() {
            if (identical(tasks[packageName], task)) tasks.remove(packageName);
          });
      return task;
    });
  }

  Map<int, Category> _categoriesById = Map();

  // Cached SharedPreferences instance to avoid repeated disk I/O
  SharedPreferences? _prefs;
  Future<SharedPreferences> get _prefsAsync async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  bool get initialized => _initialized;
  int get layoutVersion => _layoutVersion;

  @override
  void notifyListeners() {
    if (_disposed) return;
    _layoutVersion++;
    _sortedApplications = null;
    super.notifyListeners();
  }

  String? _pendingReorderFocusPackage;
  int? _pendingReorderFocusCategoryId;
  String? get pendingReorderFocusPackage => _pendingReorderFocusPackage;
  int? get pendingReorderFocusCategoryId => _pendingReorderFocusCategoryId;
  void clearPendingReorderFocusPackage() {
    _pendingReorderFocusPackage = null;
    _pendingReorderFocusCategoryId = null;
  }

  void setPendingReorderFocus(String packageName, int categoryId) {
    _pendingReorderFocusPackage = packageName;
    _pendingReorderFocusCategoryId = categoryId;
  }

  final Set<String> _dirtyImagePackages = {};
  bool consumeDirtyImage(String packageName) =>
      _dirtyImagePackages.remove(packageName);

  // Read by ~26 call sites, many inside build(); sort once per change instead
  // of on every read. Cleared in notifyListeners and wherever _applications is
  // replaced or extended before an await / without notifying.
  List<App>? _sortedApplications;
  List<App> get applications => _sortedApplications ??= UnmodifiableListView(
    _applications.values.sortedBy((application) => application.name),
  );

  List<LauncherSection> get launcherSections =>
      List.unmodifiable(_launcherSections);
  List<Category> get categories => _categoriesById.values
      .map((category) => category.unmodifiable())
      .toList(growable: false);

  AppsService(this._lumaChannel, this._database) {
    unawaited(initialize());
  }

  Future<void> initialize() async {
    if (_disposed || _initializing || _initialized) return;
    _initializing = true;
    _initializationError = null;
    notifyListeners();
    try {
      await _init();
    } catch (error) {
      _initializationError = error;
      debugPrint('Apps: initialization failed: $error');
      notifyListeners();
    } finally {
      _initializing = false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _lumaChannel.removeAppsChangedListener(_onAppsChanged);
    super.dispose();
  }

  void _onAppsChanged(Map<String, dynamic> event) {
    _eventQueue = _eventQueue
        .then((_) async {
          if (!_disposed) await _handleAppsChanged(event);
        })
        .catchError((Object error) {
          debugPrint('Apps: package refresh failed: $error');
        });
  }

  Future<void> _init() async {
    await _refreshState(shouldNotifyListeners: false);
    if (_database.wasCreated) {
      await _initDefaultCategories();
    }

    if (_disposed) return;
    _lumaChannel.addAppsChangedListener(_onAppsChanged);

    _initialized = true;
    notifyListeners();

    // Artwork is requested lazily by visible tiles. Avoid decoding every app at boot.
  }

  Future<void> _handleAppsChanged(Map<String, dynamic> event) async {
    String? changedPackageName;
    if (event.containsKey('packageName')) {
      changedPackageName = event['packageName'];
    } else if (event.containsKey('activityInfo')) {
      changedPackageName = event['activityInfo']['packageName'];
    }

    if (changedPackageName != null) {
      _invalidateArtwork(changedPackageName);
    }

    switch (event["action"]) {
      case "PACKAGE_ADDED":
      case "PACKAGE_CHANGED":
        Map<dynamic, dynamic> applicationInfo = event['activityInfo'];
        await _database.persistApps([_buildAppCompanion(applicationInfo)]);

        App newApp = App.fromSystem(applicationInfo);
        App? existingApp = _applications[newApp.packageName];

        if (existingApp != null) {
          newApp.hidden = existingApp.hidden;
          newApp.lastLaunchedAt = existingApp.lastLaunchedAt;
          newApp.categoryOrders = Map.from(existingApp.categoryOrders);
          for (int categoryId in newApp.categoryOrders.keys) {
            if (_categoriesById.containsKey(categoryId)) {
              Category category = _categoriesById[categoryId]!;
              int index = category.applications.indexOf(existingApp);
              if (index != -1) {
                category.applications[index] = newApp;
              } else {
                category.applications.add(newApp);
              }
            }
          }
          _applications[newApp.packageName] = newApp;
        } else {
          _applications[newApp.packageName] = newApp;
          _sortedApplications = null; // readers during the await below
          final targetCategory = _findTargetCategoryForNewApp();
          if (targetCategory != null) {
            await addToCategory(
              newApp,
              targetCategory,
              shouldNotifyListeners: false,
            );
          }
        }
        break;
      case "PACKAGES_AVAILABLE":
        List<dynamic> applicationsInfo = event["activitiesInfo"];
        await _database.persistApps((applicationsInfo).map(_buildAppCompanion));

        for (Map<dynamic, dynamic> applicationInfo in applicationsInfo) {
          App newApp = App.fromSystem(applicationInfo);
          App? existingApp = _applications[newApp.packageName];

          if (existingApp != null) {
            newApp.hidden = existingApp.hidden;
            newApp.lastLaunchedAt = existingApp.lastLaunchedAt;
            newApp.categoryOrders = Map.from(existingApp.categoryOrders);
            for (int categoryId in newApp.categoryOrders.keys) {
              if (_categoriesById.containsKey(categoryId)) {
                Category category = _categoriesById[categoryId]!;
                int index = category.applications.indexOf(existingApp);
                if (index != -1) {
                  category.applications[index] = newApp;
                } else {
                  category.applications.add(newApp);
                }
              }
            }
            _applications[newApp.packageName] = newApp;
          } else {
            _applications[newApp.packageName] = newApp;
          }
          _invalidateArtwork(newApp.packageName);
        }
        break;
      case "PACKAGE_REMOVED":
        String packageName = event['packageName'];
        await _database.deleteApps([packageName]);

        // Clear icon cache for removed app
        _invalidateArtwork(packageName);

        App? application = _applications.remove(packageName);

        if (application != null) {
          for (int categoryId in application.categoryOrders.keys) {
            if (_categoriesById.containsKey(categoryId)) {
              Category category = _categoriesById[categoryId]!;
              category.applications.remove(application);
            }
          }
        }
        break;
    }

    notifyListeners();
  }

  AppsCompanion _buildAppCompanion(dynamic data) {
    String? version = data["version"];
    if (version == null) {
      version = "";
    }

    return AppsCompanion(
      packageName: Value(data["packageName"]),
      name: Value(data["name"]),
      version: Value(version),
      hidden: const Value.absent(),
    );
  }

  Future<void> _initDefaultCategories() {
    final allApps = _applications.values.where(
      (application) => !application.hidden,
    );
    final defaultFavoriteLauncherPackageNames = [
      'com.google.android.youtube.tv',
      'com.netflix.ninja',
      'in.startv.hotstar',
      'com.amazon.amazonvideo.livingroom',
      'com.sonyliv',
      'com.graymatrix.did',
      'com.jio.media.jiotvplus',
    ];

    return _database.transaction(() async {
      if (allApps.isNotEmpty) {
        int categoryId = await addCategory(
          "All Apps",
          type: CategoryType.grid,
          shouldNotifyListeners: false,
        );

        Category allAppsCategory = _categoriesById[categoryId]!;
        for (final app in allApps) {
          await addToCategory(
            app,
            allAppsCategory,
            shouldNotifyListeners: false,
          );
        }
      }

      final int favoritesId = await addCategory(
        "Favorites",
        shouldNotifyListeners: false,
      );
      final Category favoritesCategory = _categoriesById[favoritesId]!;
      final Category? allAppsCategory = _getAppsCategory();
      final initialFavorites = [
        ...defaultFavoriteLauncherPackageNames.where(_applications.containsKey),
        ...allApps
            .where(
              (app) => !defaultFavoriteLauncherPackageNames.contains(
                app.packageName,
              ),
            )
            .map((app) => app.packageName),
      ].take(6);
      for (final packageName in initialFavorites) {
        final app = _applications[packageName];
        if (app != null && !app.hidden) {
          await addToCategory(
            app,
            favoritesCategory,
            shouldNotifyListeners: false,
          );
          if (allAppsCategory != null) {
            await removeFromCategory(app, allAppsCategory);
          }
        }
      }
    });
  }

  Future<void> _refreshState({bool shouldNotifyListeners = true}) async {
    Future<List<App>> appsFromDatabaseFuture = _database.getApplications();
    Future<List<AppCategory>> appsCategoriesFuture = _database
        .getAppsCategories();
    Future<List<Category>> categoriesFuture = _database.getCategories();
    Future<List<LauncherSpacer>> spacersFuture = _database.getLauncherSpacers();
    final initial = await Future.wait<Object>([
      appsFromDatabaseFuture,
      appsCategoriesFuture,
      categoriesFuture,
      spacersFuture,
      _lumaChannel.getApplications().timeout(const Duration(seconds: 20)),
    ]);
    final appsFromSystem = initial.last as List<Map<dynamic, dynamic>>;
    Iterable<MapEntry<String, (Map, AppsCompanion)>> appEntries = appsFromSystem
        .map(
          (appFromSystem) => new MapEntry(appFromSystem['packageName'], (
            appFromSystem,
            _buildAppCompanion(appFromSystem),
          )),
        );
    Map<String, (Map, AppsCompanion)> appsFromSystemByPackageName =
        Map.fromEntries(appEntries);

    List<App> appsFromDatabase = await appsFromDatabaseFuture;
    final Iterable<App> appsRemovedFromSystem = appsFromDatabase.where(
      (app) => !appsFromSystemByPackageName.containsKey(app.packageName),
    );

    final List<String> uninstalledApplications = [];
    for (App app in appsRemovedFromSystem) {
      String packageName = app.packageName;

      // TODO: Is this really necessary? Can't we get this information from the getApplications method?
      bool appExists = await _lumaChannel.applicationExists(packageName);
      if (!appExists) {
        uninstalledApplications.add(packageName);
      }
    }

    await _database.transaction(() async {
      await _database.persistApps(
        appsFromSystemByPackageName.values.map((record) => record.$2),
      );
      await _database.deleteApps(uninstalledApplications);
    });

    appsFromDatabaseFuture = _database.getApplications();

    await Future.wait([
      appsFromDatabaseFuture,
      appsCategoriesFuture,
      categoriesFuture,
      spacersFuture,
    ]);

    appsFromDatabase = await appsFromDatabaseFuture;
    List<AppCategory> appsCategories = await appsCategoriesFuture;
    List<Category> categories = await categoriesFuture;
    List<LauncherSpacer> spacers = await spacersFuture;

    _categoriesById = Map.fromEntries(
      categories.map((category) => MapEntry(category.id, category)),
    );
    _applications = Map.fromEntries(
      appsFromDatabase.map(
        (application) => MapEntry(application.packageName, application),
      ),
    );
    _sortedApplications = null; // callers may pass shouldNotifyListeners: false

    _launcherSections.clear();
    _launcherSections.addAll(categories);
    _launcherSections.addAll(spacers);
    _launcherSections.sort((ls0, ls1) => ls0.order.compareTo(ls1.order));

    for (App application in _applications.values) {
      Map? applicationFromSystem =
          appsFromSystemByPackageName[application.packageName]?.$1;

      if (applicationFromSystem != null) {
        application.appCategory =
            (applicationFromSystem['appCategory'] as num?)?.toInt() ?? -1;
        application.installedAt =
            (applicationFromSystem['installedAt'] as num?)?.toInt() ?? 0;
        application.isGame = applicationFromSystem['isGame'] == true;
        if (applicationFromSystem.containsKey('action')) {
          application.action = applicationFromSystem['action'];
        }
        if (applicationFromSystem.containsKey('sideloaded')) {
          application.sideloaded = applicationFromSystem['sideloaded'];
        }
      }

      if (appsCategories.isNotEmpty && !application.hidden) {
        Iterable<AppCategory> currentApplicationCategories = appsCategories
            .where(
              (appCategory) =>
                  appCategory.appPackageName == application.packageName,
            );

        for (AppCategory appCategory in currentApplicationCategories) {
          if (_categoriesById.containsKey(appCategory.categoryId)) {
            Category category = _categoriesById[appCategory.categoryId]!;
            application.categoryOrders[category.id] = appCategory.order;
            category.applications.add(application);
          }
        }
      }
    }

    for (Category category in _categoriesById.values) {
      sortCategory(category);
    }

    if (shouldNotifyListeners) {
      notifyListeners();
    }
  }

  void sortCategory(Category category) {
    if (category.sort == CategorySort.alphabetical) {
      category.applications.sortBy((application) => application.name);
    } else if (category.sort == CategorySort.lastUsed) {
      category.applications.sort((a, b) {
        final aTime =
            a.lastLaunchedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bTime =
            b.lastLaunchedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bTime.compareTo(aTime); // Descending (newest first)
      });
    } else {
      category.applications.sortBy<num>(
        (application) => application.categoryOrders[category.id]!,
      );
    }
  }

  /// Finds the appropriate category for a newly installed app.
  /// Returns "All Apps" category, or falls back to first non-Favorites category.
  Category? _findTargetCategoryForNewApp() {
    if (_categoriesById.isEmpty) return null;
    return _categoriesById.values.firstWhere(
      (c) => c.name.toLowerCase() == "all apps",
      orElse: () {
        return _categoriesById.values.firstWhere(
          (c) => c.name.toLowerCase() != 'favorites',
          orElse: () => _categoriesById.values.first,
        );
      },
    );
  }

  Future<Uint8List> getAppBanner(String packageName) =>
      _loadArtwork(packageName, _bannerCache, _bannerTasks, _readAppBanner);

  Future<Uint8List> _readAppBanner(String packageName) async {
    try {
      final prefs = await _prefsAsync;
      final customBannerPath = prefs.getString('custom_banner_$packageName');
      if (customBannerPath != null) {
        final file = File(customBannerPath);
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          return bytes;
        }
      }
    } on FileSystemException {
      // File was deleted between check and read - clear stale reference
      final prefs = await _prefsAsync;
      await prefs.remove('custom_banner_$packageName');
    } catch (_) {
      // Ignore other errors reading custom banner
    }

    final bytes = await _lumaChannel.getApplicationBanner(packageName);
    return bytes;
  }

  Future<void> setCustomAppBanner(String packageName, String imagePath) async {
    final prefs = await _prefsAsync;
    await prefs.setString('custom_banner_$packageName', imagePath);
    _invalidateArtwork(packageName);
    notifyListeners();
  }

  Future<void> removeCustomAppBanner(String packageName) async {
    final prefs = await _prefsAsync;
    final customBannerPath = prefs.getString('custom_banner_$packageName');
    if (customBannerPath != null) {
      try {
        await File(customBannerPath).delete();
      } catch (_) {
        // Ignore file deletion errors
      }
    }
    await prefs.remove('custom_banner_$packageName');
    _invalidateArtwork(packageName);
    notifyListeners();
  }

  Future<bool> hasCustomBanner(String packageName) async {
    final prefs = await _prefsAsync;
    return prefs.containsKey('custom_banner_$packageName');
  }

  Future<Uint8List> getAppIcon(String packageName) => _loadArtwork(
    packageName,
    _iconCache,
    _iconTasks,
    _lumaChannel.getApplicationIcon,
  );

  Future<void> launchApp(App app) async {
    if (app.action == null) {
      await _lumaChannel.launchApp(app.packageName);
    } else {
      await _lumaChannel.launchActivityFromAction(app.action!);
    }
    // Only successful launches belong in Recently opened.
    final launchedAt = DateTime.now();
    await _database.updateApp(
      app.packageName,
      AppsCompanion(lastLaunchedAt: Value(launchedAt)),
    );
    app.lastLaunchedAt = launchedAt;
    for (final category in _categoriesById.values.where(
      (c) => c.sort == CategorySort.lastUsed,
    )) {
      sortCategory(category);
    }
    notifyListeners();
  }

  Future<void> openAppInfo(App app) =>
      _lumaChannel.openAppInfo(app.packageName);

  Future<void> uninstallApp(App app) =>
      _lumaChannel.uninstallApp(app.packageName);

  Future<void> openSettings() => _lumaChannel.openSettings();

  Future<bool> isDefaultLauncher() => _lumaChannel.isDefaultLauncher();

  Future<void> startAmbientMode() => _lumaChannel.startAmbientMode();

  Future<void> addToCategory(
    App app,
    Category category, {
    bool shouldNotifyListeners = true,
  }) async {
    int index = await _database.nextAppCategoryOrder(category.id) ?? 0;
    await _database.insertAppsCategories([
      AppsCategoriesCompanion.insert(
        categoryId: category.id,
        appPackageName: app.packageName,
        order: index,
      ),
    ]);

    if (_categoriesById.containsKey(category.id)) {
      Category categoryFound = _categoriesById[category.id]!;
      app.categoryOrders[categoryFound.id] = index;
      categoryFound.applications.add(app);

      if (shouldNotifyListeners) {
        sortCategory(categoryFound);
        notifyListeners();
      }
    }
  }

  Future<void> removeFromCategory(App application, Category category) async {
    await _database.deleteAppCategory(category.id, application.packageName);
    if (_categoriesById.containsKey(category.id)) {
      Category categoryFound = _categoriesById[category.id]!;
      application.categoryOrders.remove(categoryFound.id);
      categoryFound.applications.remove(application);

      notifyListeners();
    }
  }

  /// Auto-populates a category based on its special name.
  /// For "All Apps": adds all non-hidden apps regardless of sideloaded status.
  Future<void> autoPopulateCategory(Category category) async {
    if (!_categoriesById.containsKey(category.id)) {
      return;
    }
    Category actualCategory = _categoriesById[category.id]!;

    Iterable<App> appsToAdd;

    switch (actualCategory.name) {
      case 'All Apps':
        appsToAdd = _applications.values.where((app) => !app.hidden);
        break;
      default:
        return;
    }

    for (final app in appsToAdd) {
      await addToCategory(app, actualCategory, shouldNotifyListeners: false);
    }

    notifyListeners();
  }

  Category? _getAppsCategory() {
    return _categoriesById.values.firstWhereOrNull(
      (category) => category.name == 'All Apps',
    );
  }

  /// Gets the Favorites category, creating it if it doesn't exist
  Future<Category> getOrCreateFavoritesCategory() async {
    Category? favorites = _categoriesById.values.firstWhereOrNull(
      (category) => category.name == 'Favorites',
    );

    if (favorites != null) {
      return favorites;
    }

    int categoryId = await addCategory(
      'Favorites',
      shouldNotifyListeners: false,
    );
    return _categoriesById[categoryId]!;
  }

  /// Checks if an app is in the Favorites category
  bool isAppInFavorites(App app) {
    Category? favorites = _categoriesById.values.firstWhereOrNull(
      (category) => category.name == 'Favorites',
    );

    if (favorites == null) {
      return false;
    }

    return favorites.applications.any((a) => a.packageName == app.packageName);
  }

  /// Adds an app to Favorites and removes it from the Apps category
  Future<void> addToFavorites(App app) async {
    Category favorites = await getOrCreateFavoritesCategory();

    if (!favorites.applications.any((a) => a.packageName == app.packageName)) {
      await addToCategory(app, favorites, shouldNotifyListeners: false);
    }

    final appsCategory = _getAppsCategory();
    if (appsCategory != null &&
        appsCategory.applications.any(
          (a) => a.packageName == app.packageName,
        )) {
      await removeFromCategory(app, appsCategory);
    } else {
      notifyListeners();
    }
  }

  /// Removes an app from Favorites and puts it back in the Apps category
  Future<void> removeFromFavorites(App app) async {
    Category? favorites = _categoriesById.values.firstWhereOrNull(
      (category) => category.name == 'Favorites',
    );

    if (favorites != null) {
      await removeFromCategory(app, favorites);
    }

    final appsCategory = _getAppsCategory();
    if (appsCategory != null &&
        !appsCategory.applications.any(
          (a) => a.packageName == app.packageName,
        )) {
      await addToCategory(app, appsCategory);
    }
  }

  /// Toggles an app in/out of Favorites
  Future<void> toggleFavorite(App app) async {
    if (isAppInFavorites(app)) {
      await removeFromFavorites(app);
    } else {
      await addToFavorites(app);
    }
  }

  /// The favourites bar, in order, as package names.
  List<String> get favoritePackages => [
    for (final app
        in _categoriesById.values
                .firstWhereOrNull((category) => category.name == 'Favorites')
                ?.applications ??
            const <App>[])
      app.packageName,
  ];

  /// Makes the favourites bar exactly [packages], in that order. Apps that
  /// are no longer installed are skipped.
  Future<void> setFavoritePackages(List<String> packages) async {
    final wanted = [
      for (final package in packages.toSet())
        if (_applications.containsKey(package)) package,
    ];
    final favorites = await getOrCreateFavoritesCategory();
    for (final app in [...favorites.applications]) {
      if (!wanted.contains(app.packageName)) await removeFromFavorites(app);
    }
    for (final package in wanted) {
      if (!favorites.applications.any((app) => app.packageName == package)) {
        await addToFavorites(_applications[package]!);
      }
    }
    favorites.applications.sort(
      (a, b) =>
          wanted.indexOf(a.packageName).compareTo(wanted.indexOf(b.packageName)),
    );
    for (var i = 0; i < favorites.applications.length; i++) {
      favorites.applications[i].categoryOrders[favorites.id] = i;
    }
    await saveApplicationOrderInCategory(favorites);
  }

  Future<void> saveApplicationOrderInCategory(Category category) async {
    if (!_categoriesById.containsKey(category.id)) {
      return;
    }

    Category categoryFound = _categoriesById[category.id]!;
    List<App> applications = categoryFound.applications;
    List<AppsCategoriesCompanion> orderedAppCategories = [];

    for (int i = 0; i < applications.length; ++i) {
      orderedAppCategories.add(
        AppsCategoriesCompanion(
          categoryId: Value(categoryFound.id),
          appPackageName: Value(applications[i].packageName),
          order: Value(i),
        ),
      );
    }
    await _database.replaceAppsCategories(orderedAppCategories);
    notifyListeners();
  }

  Future<void> moveAppToAdjacentCategory(
    App app,
    Category currentCategory,
    AxisDirection direction,
  ) async {
    int currentSectionIndex = _launcherSections.indexOf(currentCategory);
    if (currentSectionIndex == -1) {
      return;
    }

    Category? targetCategory;

    // Find next valid category (skip spacers)
    if (direction == AxisDirection.down) {
      for (int i = currentSectionIndex + 1; i < _launcherSections.length; i++) {
        if (_launcherSections[i] is Category) {
          targetCategory = _launcherSections[i] as Category;
          break;
        }
      }
    } else if (direction == AxisDirection.up) {
      for (int i = currentSectionIndex - 1; i >= 0; i--) {
        if (_launcherSections[i] is Category) {
          targetCategory = _launcherSections[i] as Category;
          break;
        }
      }
    }

    if (targetCategory == null) {
      return;
    }

    // Remove from current
    await removeFromCategory(app, currentCategory);

    // Set pending focus package so AppCard can reclaim focus and reorder mode
    _pendingReorderFocusPackage = app.packageName;

    // Add to target
    // DB Insert Logic
    // 1. Get current items in target
    List<App> targetApps = targetCategory.applications;

    // 2. Adjust local list
    if (direction == AxisDirection.down) {
      targetApps.insert(0, app); // Insert at top
    } else {
      targetApps.add(app); // Insert at bottom
    }

    // 3. Update orders for all items in target category
    List<AppsCategoriesCompanion> orderedAppCategories = [];
    for (int i = 0; i < targetApps.length; ++i) {
      App a = targetApps[i];
      a.categoryOrders[targetCategory.id] = i; // Update local map
      orderedAppCategories.add(
        AppsCategoriesCompanion(
          categoryId: Value(targetCategory.id),
          appPackageName: Value(a.packageName),
          order: Value(i),
        ),
      );
    }

    // 4. Batch DB update
    await _database.replaceAppsCategories(orderedAppCategories);

    notifyListeners();
  }

  Map<String, dynamic> exportLayout() => {
    'categories': [
      for (final c in _launcherSections.whereType<Category>())
        {
          'order': c.order,
          'name': c.name,
          'sort': c.sort.name,
          'type': c.type.name,
          'columns': c.columnsCount.clamp(3, 8),
          'rowHeight': c.rowHeight.clamp(40, 400),
          'apps':
              (_applications.values
                      .where((app) => app.categoryOrders.containsKey(c.id))
                      .toList()
                    ..sort(
                      (a, b) => (a.categoryOrders[c.id] ?? 0).compareTo(
                        b.categoryOrders[c.id] ?? 0,
                      ),
                    ))
                  .map((app) => app.packageName)
                  .toList(),
        },
    ],
    'spacers': [
      for (final spacer in _launcherSections.whereType<LauncherSpacer>())
        {'height': spacer.height, 'order': spacer.order},
    ],
    'hidden': _applications.values
        .where((app) => app.hidden)
        .map((app) => app.packageName)
        .toList(),
  };

  /// Call only with a validated LauncherBackup layout. Database changes are atomic.
  Future<void> restoreLayout(Map<String, dynamic> layout) async {
    if (!_initialized) throw StateError('App collection is still loading');
    await _database.transaction(() async {
      await _database.delete(_database.appsCategories).go();
      await _database.delete(_database.categories).go();
      await _database.delete(_database.launcherSpacers).go();
      final hidden = (layout['hidden'] as List).cast<String>().toSet();
      for (final app in _applications.values) {
        await _database.updateApp(
          app.packageName,
          AppsCompanion(hidden: Value(hidden.contains(app.packageName))),
        );
      }
      var order = 0;
      for (final raw in layout['categories'] as List) {
        final c = raw as Map;
        final id = await _database.insertCategory(
          CategoriesCompanion.insert(
            name: c['name'] as String,
            order: c['order'] as int? ?? order++,
            sort: Value(CategorySort.values.byName(c['sort'])),
            type: Value(CategoryType.values.byName(c['type'])),
            columnsCount: Value(c['columns'] as int),
            rowHeight: Value(c['rowHeight'] as int),
          ),
        );
        final ids = (c['apps'] as List)
            .cast<String>()
            .where(_applications.containsKey)
            .toList();
        await _database.insertAppsCategories([
          for (var i = 0; i < ids.length; i++)
            AppsCategoriesCompanion.insert(
              categoryId: id,
              appPackageName: ids[i],
              order: i,
            ),
        ]);
      }
      for (final spacer in layout['spacers'] as List? ?? []) {
        await _database.insertSpacer(
          LauncherSpacersCompanion.insert(
            height: spacer['height'] as int,
            order: spacer['order'] as int,
          ),
        );
      }
    });
    await _refreshState();
  }

  Future<void> reorderApplication(
    Category category,
    int oldIndex,
    int newIndex,
  ) async {
    if (!_categoriesById.containsKey(category.id)) {
      return;
    }
    Category categoryFound = _categoriesById[category.id]!;
    List<App> applications = categoryFound.applications;
    App application = applications.removeAt(oldIndex);
    applications.insert(newIndex, application);
    final rows = <AppsCategoriesCompanion>[];
    for (var i = 0; i < applications.length; i++) {
      applications[i].categoryOrders[category.id] = i;
      rows.add(
        AppsCategoriesCompanion(
          categoryId: Value(category.id),
          appPackageName: Value(applications[i].packageName),
          order: Value(i),
        ),
      );
    }
    await _database.replaceAppsCategories(rows);
    notifyListeners();
  }

  Future<int> addCategory(
    String categoryName, {
    CategorySort sort = Category.Sort,
    CategoryType type = Category.Type,
    int columnsCount = Category.ColumnsCount,
    int rowHeight = Category.RowHeight,
    bool shouldNotifyListeners = true,
  }) async {
    List<CategoriesCompanion> orderedCategories = [];
    int categoryOrder = 1, newCategoryId = -1;
    for (Category category in _categoriesById.values) {
      orderedCategories.add(
        CategoriesCompanion(
          id: Value(category.id),
          order: Value(categoryOrder++),
        ),
      );
    }

    try {
      newCategoryId = await _database.transaction(() async {
        int newCategoryId = await _database.insertCategory(
          CategoriesCompanion.insert(
            name: categoryName,
            order: 0,
            sort: Value(sort),
            type: Value(type),
            columnsCount: Value(columnsCount),
            rowHeight: Value(rowHeight),
          ),
        );
        await _database.updateCategories(orderedCategories);

        return newCategoryId;
      });

      Map<int, Category> newCategories = Map();
      Category newCategory = Category(
        id: newCategoryId,
        name: categoryName,
        sort: sort,
        type: type,
        columnsCount: columnsCount,
        rowHeight: rowHeight,
        order: 0,
      );
      newCategories[newCategoryId] = newCategory;

      categoryOrder = 1;
      for (Category category in _categoriesById.values) {
        newCategories[category.id] = category;
        category.order = categoryOrder++;
      }

      _categoriesById = newCategories;
      _launcherSections.insert(0, newCategory);
      await persistSectionsOrder();

      if (shouldNotifyListeners) {
        notifyListeners();
      }
    } catch (ex) {}

    return newCategoryId;
  }

  Future<void> updateCategory(
    int categoryId,
    String name,
    CategorySort sort,
    CategoryType type,
    int columnsCount,
    int rowHeight, {
    bool shouldNotifyListeners = true,
  }) async {
    Category? category = _categoriesById[categoryId];
    assert(category != null);

    await _database.updateCategory(
      categoryId,
      CategoriesCompanion(
        name: Value(name),
        sort: Value(sort),
        type: Value(type),
        columnsCount: Value(columnsCount),
        rowHeight: Value(rowHeight),
      ),
    );

    CategorySort oldSort = category!.sort;

    category.name = name;
    category.sort = sort;
    category.type = type;
    category.columnsCount = columnsCount;
    category.rowHeight = rowHeight;

    if (oldSort != sort) {
      sortCategory(category);
    }

    if (shouldNotifyListeners) {
      notifyListeners();
    }
  }

  Future<void> addSpacer(int height) async {
    int order = launcherSections.length;
    int spacerId = await _database.insertSpacer(
      LauncherSpacersCompanion.insert(height: height, order: order),
    );

    _launcherSections.add(
      LauncherSpacer(id: spacerId, height: height, order: order),
    );

    notifyListeners();
  }

  Future<void> updateSpacerHeight(LauncherSpacer spacer, int height) async {
    await _database.updateSpacer(
      spacer.id,
      LauncherSpacersCompanion(height: Value(height)),
    );

    spacer.height = height;
    notifyListeners();
  }

  Future<void> renameCategory(Category category, String categoryName) async {
    await _database.updateCategory(
      category.id,
      CategoriesCompanion(name: Value(categoryName)),
    );

    if (_categoriesById.containsKey(category.id)) {
      Category categoryFound = _categoriesById[category.id]!;
      categoryFound.name = categoryName;
      notifyListeners();
    }
  }

  Future<void> deleteSection(int index) async {
    assert(index < _launcherSections.length);

    LauncherSection section = _launcherSections[index];
    if (section is Category) {
      await _database.deleteCategory(section.id);
      _categoriesById.remove(section.id);
    } else {
      await _database.deleteSpacer(section.id);
    }

    _launcherSections.removeAt(index);

    notifyListeners();
  }

  void moveSectionInMemory(int oldIndex, int newIndex) {
    if (oldIndex < 0 ||
        oldIndex >= _launcherSections.length ||
        newIndex < 0 ||
        newIndex >= _launcherSections.length)
      return;

    final section = _launcherSections.removeAt(oldIndex);
    _launcherSections.insert(newIndex, section);
    notifyListeners();
  }

  Future<void> persistSectionsOrder() async {
    List<CategoriesCompanion> orderedCategories = [];
    List<LauncherSpacersCompanion> orderedSpacers = [];

    for (int i = 0; i < _launcherSections.length; ++i) {
      LauncherSection section = _launcherSections[i];
      // Update the order property on the object itself
      if (section is Category)
        section.order = i;
      else if (section is LauncherSpacer)
        section.order = i;

      if (section is Category) {
        orderedCategories.add(
          CategoriesCompanion(id: Value(section.id), order: Value(i)),
        );
      } else {
        orderedSpacers.add(
          LauncherSpacersCompanion(id: Value(section.id), order: Value(i)),
        );
      }
    }

    await Future.wait([
      _database.updateCategories(orderedCategories),
      _database.updateSpacers(orderedSpacers),
    ]);
  }

  Future<void> moveSection(int oldIndex, int newIndex) async {
    moveSectionInMemory(oldIndex, newIndex);
    await persistSectionsOrder();
  }

  Future<void> hideApplication(App application) async {
    await _database.updateApp(
      application.packageName,
      const AppsCompanion(hidden: Value(true)),
    );

    if (_applications.containsKey(application.packageName)) {
      App applicationFound = _applications[application.packageName]!;
      applicationFound.hidden = true;

      for (int categoryId in applicationFound.categoryOrders.keys) {
        if (_categoriesById.containsKey(categoryId)) {
          Category category = _categoriesById[categoryId]!;
          category.applications.removeWhere(
            (application0) =>
                application0.packageName == application.packageName,
          );
        }
      }

      notifyListeners();
    }
  }

  Future<void> showApplication(App application) async {
    await _database.updateApp(
      application.packageName,
      const AppsCompanion(hidden: Value(false)),
    );

    if (_applications.containsKey(application.packageName)) {
      App applicationFound = _applications[application.packageName]!;
      applicationFound.hidden = false;

      for (int categoryId in application.categoryOrders.keys) {
        if (_categoriesById.containsKey(categoryId)) {
          Category category = _categoriesById[categoryId]!;
          category.applications.add(application);
          sortCategory(category);
        }
      }

      notifyListeners();
    }
  }

  Future<void> setCategoryType(
    Category category,
    CategoryType type, {
    bool shouldNotifyListeners = true,
  }) async {
    await _database.updateCategory(
      category.id,
      CategoriesCompanion(type: Value(type)),
    );

    if (_categoriesById.containsKey(category.id)) {
      Category categoryFound = _categoriesById[category.id]!;
      categoryFound.type = type;

      if (shouldNotifyListeners) {
        notifyListeners();
      }
    }
  }

  Future<void> setCategorySort(Category category, CategorySort sort) async {
    await _database.updateCategory(
      category.id,
      CategoriesCompanion(sort: Value(sort)),
    );
    if (_categoriesById.containsKey(category.id)) {
      Category categoryFound = _categoriesById[category.id]!;
      categoryFound.sort = sort;
      sortCategory(categoryFound);

      notifyListeners();
    }
  }

  Future<void> setCategoryColumnsCount(
    Category category,
    int columnsCount,
  ) async {
    await _database.updateCategory(
      category.id,
      CategoriesCompanion(columnsCount: Value(columnsCount)),
    );

    if (_categoriesById.containsKey(category.id)) {
      Category categoryFound = _categoriesById[category.id]!;
      categoryFound.columnsCount = columnsCount;

      notifyListeners();
    }
  }

  Future<void> setCategoryRowHeight(Category category, int rowHeight) async {
    await _database.updateCategory(
      category.id,
      CategoriesCompanion(rowHeight: Value(rowHeight)),
    );

    if (_categoriesById.containsKey(category.id)) {
      Category categoryFound = _categoriesById[category.id]!;
      categoryFound.rowHeight = rowHeight;
      notifyListeners();
    }
  }
}
