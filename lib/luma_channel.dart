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

import 'package:flutter/services.dart';

class LumaChannel {
  final _appsListeners =
      <void Function(Map<String, dynamic>), StreamSubscription<dynamic>>{};
  final _networkListeners =
      <void Function(Map<String, dynamic>), StreamSubscription<dynamic>>{};
  static const _methodChannel = MethodChannel('app.luma.tvlauncher/method');
  static const _appsEventChannel = EventChannel(
    'app.luma.tvlauncher/event_apps',
  );
  static const _networkEventChannel = EventChannel(
    'app.luma.tvlauncher/event_network',
  );

  static const _watchNextMaxItems = 10;

  Future<List<Map<dynamic, dynamic>>> getApplications() async {
    List<Map<dynamic, dynamic>>? applications = await _methodChannel
        .invokeListMethod("getApplications");
    return applications!;
  }

  Future<Uint8List> getApplicationBanner(String packageName) async {
    Uint8List bytes = await _methodChannel.invokeMethod(
      "getApplicationBanner",
      packageName,
    );
    return bytes;
  }

  Future<Uint8List> getApplicationIcon(String packageName) async {
    Uint8List bytes = await _methodChannel.invokeMethod(
      "getApplicationIcon",
      packageName,
    );
    return bytes;
  }

  Future<bool> applicationExists(String packageName) async =>
      await _methodChannel.invokeMethod('applicationExists', packageName);

  Future<void> launchActivityFromAction(String action) async {
    final launched = await _methodChannel.invokeMethod<bool>(
      'launchActivityFromAction',
      action,
    );
    if (launched == false)
      throw PlatformException(
        code: 'launch_failed',
        message: 'Could not open this app.',
      );
  }

  Future<void> launchApp(String packageName) async {
    final launched = await _methodChannel.invokeMethod<bool>(
      'launchApp',
      packageName,
    );
    if (launched == false)
      throw PlatformException(
        code: 'launch_failed',
        message: 'Could not open this app.',
      );
  }

  static void Function(bool alreadyHome)? _homeHandler;
  static final _voiceEvents =
      StreamController<Map<String, dynamic>>.broadcast();
  static void _ensureCallbacks() {
    _methodChannel.setMethodCallHandler((call) async {
      if (call.method == 'homePressed') {
        _homeHandler?.call(call.arguments == true);
      }
      if (call.method == 'voiceEvent' && call.arguments is Map) {
        _voiceEvents.add(Map<String, dynamic>.from(call.arguments as Map));
      }
      if (call.method == 'notificationsChanged') _notificationEvents.add(null);
    });
  }

  /// HDMI and other passthrough inputs; empty on streaming boxes.
  Future<List<Map<String, dynamic>>> getTvInputs() async {
    final items = await _methodChannel.invokeListMethod<Map>('getTvInputs');
    return [
      for (final item in items ?? const []) Map<String, dynamic>.from(item),
    ];
  }

  Future<bool> switchTvInput(String id) async =>
      await _methodChannel.invokeMethod<bool>('switchTvInput', id) ?? false;

  /// When the sleep timer ends, or null when it is off.
  Future<DateTime?> getSleepTimer() async {
    final end = await _methodChannel.invokeMethod<num>('getSleepTimer') ?? 0;
    return end > 0 ? DateTime.fromMillisecondsSinceEpoch(end.toInt()) : null;
  }

  /// Minutes from now; 0 turns the timer off.
  Future<DateTime?> setSleepTimer(int minutes) async {
    final end =
        await _methodChannel.invokeMethod<num>('setSleepTimer', minutes) ?? 0;
    return end > 0 ? DateTime.fromMillisecondsSinceEpoch(end.toInt()) : null;
  }

  Future<bool> canTurnOffTv() async =>
      await _methodChannel.invokeMethod<bool>('canTurnOffTv') ?? false;

  Future<bool> requestTurnOffPermission() async =>
      await _methodChannel.invokeMethod<bool>('requestTurnOffPermission') ??
      false;

  static final _notificationEvents = StreamController<void>.broadcast();

  /// Fires whenever a TV notification is posted or removed.
  Stream<void> get notificationEvents {
    _ensureCallbacks();
    return _notificationEvents.stream;
  }

  Future<bool> notificationAccess() async =>
      await _methodChannel.invokeMethod<bool>('notificationAccess') ?? false;

  Future<List<Map<String, dynamic>>> getNotifications() async {
    final items = await _methodChannel.invokeListMethod<Map>(
      'getNotifications',
    );
    return [
      for (final item in items ?? const []) Map<String, dynamic>.from(item),
    ];
  }

  Future<bool> openNotification(String key) async =>
      await _methodChannel.invokeMethod<bool>('openNotification', key) ?? false;

  Future<bool> dismissNotification(String key) async =>
      await _methodChannel.invokeMethod<bool>('dismissNotification', key) ??
      false;

  Future<int> dismissAllNotifications() async =>
      await _methodChannel.invokeMethod<int>('dismissAllNotifications') ?? 0;

  /// False when the TV has no settings screen for notification access.
  Future<bool> openNotificationAccessSettings() async =>
      await _methodChannel.invokeMethod<bool>(
        'openNotificationAccessSettings',
      ) ??
      false;

  /// Stops the TV from turning its screen off while Luma is showing.
  Future<void> setKeepScreenOn(bool value) async {
    try {
      await _methodChannel.invokeMethod<bool>('setKeepScreenOn', value);
    } catch (_) {
      /* Older builds without the method keep the TV's own setting. */
    }
  }

  /// [alreadyHome] is true when Home was pressed while Luma was on screen.
  void setHomePressedHandler(void Function(bool alreadyHome)? handler) {
    _homeHandler = handler;
    _ensureCallbacks();
  }

  /// Removes [handler] only if it is still the one in use. A home screen that
  /// is being replaced (a profile switch rebuilds it) closes after the new
  /// one has set its own handler, and must not clear that.
  void clearHomePressedHandler(void Function(bool alreadyHome) handler) {
    if (identical(_homeHandler, handler)) _homeHandler = null;
  }

  Stream<Map<String, dynamic>> get voiceEvents {
    _ensureCallbacks();
    return _voiceEvents.stream;
  }

  Future<void> startVoiceSearch() async =>
      await _methodChannel.invokeMethod('startVoiceSearch');
  Future<void> stopVoiceSearch() async =>
      await _methodChannel.invokeMethod('stopVoiceSearch');

  Future<void> openHomeSettings() async =>
      await _methodChannel.invokeMethod('openHomeSettings');

  Future<Map<String, dynamic>> getConnectionStatus() async =>
      Map<String, dynamic>.from(
        await _methodChannel.invokeMethod<Map>('getConnectionStatus') ?? {},
      );
  Future<void> requestBluetoothStatus() async =>
      _methodChannel.invokeMethod('requestBluetoothStatus');
  Future<String> saveLocalBackup(String json) async =>
      await _methodChannel.invokeMethod<String>('saveLocalBackup', json) ??
      'Backup saved.';
  Future<String?> readLocalBackup() =>
      _methodChannel.invokeMethod<String>('readLocalBackup');
  Future<bool> exportBackup(String json) async =>
      await _methodChannel.invokeMethod<bool>('exportBackup', json) ?? false;
  Future<String?> importBackup() =>
      _methodChannel.invokeMethod<String>('importBackup');
  Future<bool> openQuickSettings(String section) async =>
      await _methodChannel.invokeMethod<bool>('openQuickSettings', section) ??
      false;

  Future<void> openSettings() async =>
      await _methodChannel.invokeMethod('openSettings');

  Future<void> openAppInfo(String packageName) async =>
      await _methodChannel.invokeMethod('openAppInfo', packageName);

  Future<void> uninstallApp(String packageName) async =>
      await _methodChannel.invokeMethod('uninstallApp', packageName);

  Future<bool> isDefaultLauncher() async =>
      await _methodChannel.invokeMethod('isDefaultLauncher');

  /// isLowRamDevice, totalMemBytes, memoryClassMb, sdkInt, model.
  Future<Map<String, dynamic>> getDeviceProfile() async {
    final profile = await _methodChannel.invokeMapMethod<String, dynamic>(
      'getDeviceProfile',
    );
    return profile ?? const {};
  }

  Future<bool> checkForGetContentAvailability() async =>
      await _methodChannel.invokeMethod("checkForGetContentAvailability");

  Future<Map<String, dynamic>> getActiveNetworkInformation() async {
    Map<dynamic, dynamic> map = await _methodChannel.invokeMethod(
      "getActiveNetworkInformation",
    );
    return map.cast<String, dynamic>();
  }

  Future<int> getDailyWifiUsage() async {
    try {
      final int usage = await _methodChannel.invokeMethod("getDailyWifiUsage");
      return usage;
    } on PlatformException catch (_) {
      return -1;
    }
  }

  Future<int> getWeeklyWifiUsage() async {
    try {
      final int usage = await _methodChannel.invokeMethod("getWeeklyWifiUsage");
      return usage;
    } on PlatformException catch (_) {
      return -1;
    }
  }

  Future<int> getMonthlyWifiUsage() async {
    try {
      final int usage = await _methodChannel.invokeMethod(
        "getMonthlyWifiUsage",
      );
      return usage;
    } on PlatformException catch (_) {
      return -1;
    }
  }

  Future<bool> checkUsageStatsPermission() async =>
      await _methodChannel.invokeMethod("checkUsageStatsPermission");

  Future<void> requestUsageStatsPermission() async =>
      await _methodChannel.invokeMethod("requestUsageStatsPermission");

  Future<void> openWifiSettings() async =>
      await _methodChannel.invokeMethod("openWifiSettings");

  Future<void> startAmbientMode() async =>
      await _methodChannel.invokeMethod("startAmbientMode");

  Future<bool> checkMediaPermissions() async =>
      await _methodChannel.invokeMethod("checkMediaPermissions");

  Future<void> requestMediaPermissions() async =>
      await _methodChannel.invokeMethod("requestMediaPermissions");

  Future<bool> checkMediaPermission(String type) async =>
      await _methodChannel.invokeMethod<bool>('checkMediaPermissions', type) ??
      false;

  Future<void> requestMediaPermission(String type) =>
      _methodChannel.invokeMethod<void>('requestMediaPermissions', type);

  Future<Uint8List?> getMediaStoreImageThumbnail(String uri) => _methodChannel
      .invokeMethod<Uint8List>('getMediaStoreImageThumbnail', uri);

  Future<void> copyContentUriToFile(String uri, String destination) =>
      _methodChannel.invokeMethod<void>('copyContentUriToFile', {
        'uri': uri,
        'destination': destination,
      });

  Future<List<Map<String, dynamic>>> getMediaStoreImages() async {
    List<Map<dynamic, dynamic>>? images = await _methodChannel.invokeListMethod(
      "getMediaStoreImages",
    );
    return images?.map((e) => e.cast<String, dynamic>()).toList() ?? [];
  }

  Future<List<Map<String, dynamic>>> getMediaStoreVideos() async {
    List<Map<dynamic, dynamic>>? videos = await _methodChannel.invokeListMethod(
      "getMediaStoreVideos",
    );
    return videos?.map((e) => e.cast<String, dynamic>()).toList() ?? [];
  }

  Future<Uint8List?> getMediaStoreVideoThumbnail(int id, {String? path}) async {
    try {
      return await _methodChannel.invokeMethod<Uint8List>(
        "getMediaStoreVideoThumbnail",
        {"id": id, "path": path},
      );
    } on PlatformException {
      return null;
    }
  }

  Future<bool> installApk(String apkPath) async =>
      await _methodChannel.invokeMethod("installApk", apkPath);

  Future<void> requestInstallUnknownAppsPermission() async =>
      await _methodChannel.invokeMethod("requestInstallUnknownAppsPermission");

  void addAppsChangedListener(void Function(Map<String, dynamic>) listener) {
    removeAppsChangedListener(listener);
    _appsListeners[listener] = _appsEventChannel.receiveBroadcastStream().listen(
      (event) {
        if (event is Map) listener(event.cast<String, dynamic>());
      },
      onError: (Object error) {
        // Package broadcasts are optional; a platform stream failure must not crash Home.
      },
    );
  }

  void removeAppsChangedListener(void Function(Map<String, dynamic>) listener) {
    _appsListeners.remove(listener)?.cancel();
  }

  void addNetworkChangedListener(void Function(Map<String, dynamic>) listener) {
    removeNetworkChangedListener(listener);
    _networkListeners[listener] = _networkEventChannel
        .receiveBroadcastStream()
        .listen(
          (event) {
            if (event is Map) listener(event.cast<String, dynamic>());
          },
          onError: (Object error) {
            // Retain the last network state until the next explicit refresh.
          },
        );
  }

  void removeNetworkChangedListener(
    void Function(Map<String, dynamic>) listener,
  ) {
    _networkListeners.remove(listener)?.cancel();
  }

  // Watch Next / TV Channels API
  Future<bool> checkWatchNextPermission() async =>
      await _methodChannel.invokeMethod('checkWatchNextPermission') ?? false;

  Future<void> requestWatchNextPermission() async =>
      await _methodChannel.invokeMethod('requestWatchNextPermission');

  Future<List<Map<dynamic, dynamic>>> getWatchNextItems() async {
    try {
      var result = await _methodChannel.invokeMethod(
        'getWatchNextItems',
        _watchNextMaxItems,
      );
      if (result == null) return [];
      return (result as List).cast<Map<dynamic, dynamic>>();
    } on PlatformException {
      rethrow;
    }
  }

  Future<bool> launchWatchNextItem(
    String? packageName,
    String? contentId,
    String? action,
  ) async {
    try {
      var result = await _methodChannel.invokeMethod('launchWatchNextItem', {
        'packageName': packageName,
        'contentId': contentId,
        'action': action,
      });
      return result ?? false;
    } on PlatformException {
      return false;
    } catch (e) {
      return false;
    }
  }

  /// Load image bytes from a content:// URI (for Watch Next posters)
  Future<Uint8List> loadContentUriImage(String contentUri) async {
    try {
      var result = await _methodChannel.invokeMethod(
        'loadContentUriImage',
        contentUri,
      );
      return result ?? Uint8List(0);
    } on PlatformException {
      return Uint8List(0);
    } catch (e) {
      return Uint8List(0);
    }
  }
}
