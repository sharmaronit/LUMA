/*
 * FLauncher
 * Copyright (C) 2021  Oscar Rojas
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
import 'package:luma/luma_channel.dart';
import 'package:flutter/material.dart';

enum NetworkType { Cellular, Wifi, Vpn, Wired, Unknown }

// https://developer.android.com/reference/android/telephony/TelephonyManager#NETWORK_TYPE_CDMA
enum CellularNetworkType {
  Unknown, // 0
  Gprs, // 1
  Edge, // 2
  Umts, // 3
  Cdma, // 4
  EvdoZero, // 5
  EvdoA, // 6
  Unused_1, // 7
  Hsdpa, // 8
  Hsupa, // 9
  Hspa, // 10
  Iden, // 11
  EvdoB, // 12
  Lte, // 13
  Ehrpd, // 14
  Hspap, // 15
  Gsm, // 16
  TdScdma, // 17
  Iwlan, // 18
  Unused_2, // 19
  Nr, // 20
}

class NetworkService extends ChangeNotifier {
  final LumaChannel _channel;

  bool _hasInternetAccess;
  CellularNetworkType _cellularNetworkType;
  NetworkType _networkType;
  int _wirelessNetworkSignalLevel;
  int _dailyWifiUsage; // In bytes
  bool _hasUsageStatsPermission;
  Timer? _usageTimer;
  bool _disposed = false;
  bool _refreshing = false;

  NetworkService(this._channel)
    : _hasInternetAccess = false,
      _cellularNetworkType = CellularNetworkType.Unknown,
      _networkType = NetworkType.Unknown,
      _wirelessNetworkSignalLevel = 0,
      _dailyWifiUsage = 0,
      _hasUsageStatsPermission = false {
    _channel.addNetworkChangedListener(_onNetworkChanged);

    unawaited(_refreshNetwork());
    unawaited(refreshPermissionAndUsage());
  }

  Future<void> _refreshNetwork() async {
    try {
      final map = await _channel.getActiveNetworkInformation();
      if (_disposed || map.isEmpty) return;
      _getNetworkInformation(map);
      notifyListeners();
    } catch (error) {
      debugPrint('Network: status unavailable: $error');
    }
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  Future<void> requestPermission() async {
    await _channel.requestUsageStatsPermission();
    // Wait a bit for user to return, or just rely on Lifecycle, but here we can't easily hook into lifecycle.
    // We can assume if they clicked it, they might come back.
    // Ideally we recheck when app resumes. For now let's just recheck after a delay or expose a method to recheck.
  }

  // Call this when app resumes
  Future<void> refreshPermissionAndUsage() async {
    if (_disposed || _refreshing) return;
    _refreshing = true;
    try {
      final allowed = await _channel.checkUsageStatsPermission();
      if (_disposed) return;
      _hasUsageStatsPermission = allowed;
      if (allowed) {
        await _fetchUsage();
        if (!_disposed && !(_usageTimer?.isActive ?? false)) {
          _usageTimer = Timer.periodic(
            const Duration(minutes: 5),
            (_) => _fetchUsage(),
          );
        }
      } else {
        _usageTimer?.cancel();
        _usageTimer = null;
        _dailyWifiUsage = 0;
      }
      notifyListeners();
    } catch (error) {
      debugPrint('Network: usage access unavailable: $error');
    } finally {
      _refreshing = false;
    }
  }

  Future<void> openWifiSettings() async {
    await _channel.openWifiSettings();
  }

  Future<void> _fetchUsage() async {
    // This will be called with the current period from the widget
    // For now, default to daily
    int usage;
    try {
      usage = await _channel.getDailyWifiUsage();
    } catch (error) {
      debugPrint('Network: usage unavailable: $error');
      return;
    }
    if (!_disposed && usage >= 0) {
      _dailyWifiUsage = usage;
      notifyListeners();
    }
  }

  Future<int> getWifiUsageForPeriod(String period) async {
    switch (period) {
      case 'daily':
        return await _channel.getDailyWifiUsage();
      case 'weekly':
        return await _channel.getWeeklyWifiUsage();
      case 'monthly':
        return await _channel.getMonthlyWifiUsage();
      default:
        return await _channel.getDailyWifiUsage();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _channel.removeNetworkChangedListener(_onNetworkChanged);
    _usageTimer?.cancel();
    super.dispose();
  }

  bool get hasInternetAccess => _hasInternetAccess;
  CellularNetworkType get cellularNetworkType => _cellularNetworkType;
  NetworkType get networkType => _networkType;
  int get wirelessNetworkSignalLevel => _wirelessNetworkSignalLevel;
  int get dailyWifiUsage => _dailyWifiUsage;
  bool get hasUsageStatsPermission => _hasUsageStatsPermission;

  CellularNetworkType _getCellularNetworkType(int index) {
    if (index < 0 || index >= CellularNetworkType.values.length) {
      return CellularNetworkType.Unknown;
    }
    CellularNetworkType type = CellularNetworkType.values[index];
    if (type == CellularNetworkType.Unused_1 ||
        type == CellularNetworkType.Unused_2) {
      type = CellularNetworkType.Unknown;
    }

    return type;
  }

  void _getNetworkInformation(Map<String, dynamic> map) {
    final networkTypeInt = map["networkType"];
    _hasInternetAccess = map["internetAccess"] == true;
    _networkType =
        networkTypeInt is int &&
            networkTypeInt >= 0 &&
            networkTypeInt < NetworkType.values.length
        ? NetworkType.values[networkTypeInt]
        : NetworkType.Unknown;
    _wirelessNetworkSignalLevel = 0;

    if (_networkType == NetworkType.Cellular ||
        _networkType == NetworkType.Wifi) {
      _wirelessNetworkSignalLevel =
          (map["wirelessSignalLevel"] as num?)?.toInt() ?? 0;
    }
  }

  void _onNetworkChanged(Map<String, dynamic> event) {
    if (_disposed) return;
    switch (event["name"]) {
      case "NETWORK_AVAILABLE":
        Map<dynamic, dynamic> map = event["arguments"];
        _getNetworkInformation(map.cast<String, dynamic>());
        break;
      case "NETWORK_UNAVAILABLE":
        _hasInternetAccess = false;
        _networkType = NetworkType.Unknown;
        break;
      case "CAPABILITIES_CHANGED":
        Map<dynamic, dynamic> map = event["arguments"];
        _getNetworkInformation(map.cast<String, dynamic>());
        break;
      case "CELLULAR_STATE_CHANGED":
        final index = event["arguments"];
        _cellularNetworkType = _getCellularNetworkType(
          index is int ? index : -1,
        );
        break;
    }

    notifyListeners();
  }
}
