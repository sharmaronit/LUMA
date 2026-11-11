import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/watch_next_item.dart';

/// Local preferences only. Provider items and launch links remain provider-owned.
class ProgrammeEntry {
  const ProgrammeEntry(this.item, this._provider, {this.asset});
  final WatchNextItem item;
  final String _provider;
  String get provider =>
      ProgrammeLibrary.shared.providerNames[item.packageName] ?? _provider;
  final String? asset;
  String get key =>
      '${item.packageName ?? "preview"}:${item.contentId ?? item.id}';
  Map<String, dynamic> toMap() => {
    'item': item.toMap(),
    'provider': provider,
    'asset': asset,
  };
  factory ProgrammeEntry.fromMap(Map<String, dynamic> map) => ProgrammeEntry(
    WatchNextItem.fromMap(map['item'] as Map),
    map['provider'] as String,
    asset: map['asset'] as String?,
  );
}

class ProgrammeLibrary extends ChangeNotifier {
  static final shared = ProgrammeLibrary();
  List<ProgrammeEntry> source = [];
  Map<String, String> providerNames = {};
  Map<String, String> installedSources = {};
  bool sourceAccessAllowed = true;
  String? sourceError;
  void setSourceError(String message) {
    sourceError = message;
    notifyListeners();
  }

  bool refreshing = false;
  void setRefreshing(bool value) {
    if (refreshing == value) return;
    refreshing = value;
    notifyListeners();
  }

  Future<void> Function()? refreshSources, requestSourceAccess;
  void registerSources(Map<String, String> apps, {bool allowed = true}) {
    if (mapEquals(installedSources, apps) && sourceAccessAllowed == allowed)
      return;
    installedSources = Map.unmodifiable(apps);
    sourceAccessAllowed = allowed;
    notifyListeners();
  }

  Map<String, String> get availableSources => {
    ...installedSources,
    for (final entry in source) sourceId(entry): entry.provider,
  };
  final Map<String, ProgrammeEntry> saved = {};
  final Set<String> hidden = {};
  final Set<String> disabledSources = {};
  Future<ImageProvider?> Function(String package)? loadAppIcon;
  String sourceStatus(String id) {
    if (!sourceAccessAllowed) return 'TV content access required';
    final count = source.where((entry) => sourceId(entry) == id).length;
    return count == 0
        ? 'No shared titles yet'
        : '$count shared ${count == 1 ? "title" : "titles"}';
  }

  String sourceId(ProgrammeEntry entry) =>
      entry.item.packageName ?? entry.provider;
  bool sourceEnabled(ProgrammeEntry entry) =>
      !disabledSources.contains(sourceId(entry));
  Future<void> setSourceEnabled(String source, bool enabled) async {
    await ready();
    final wasDisabled = disabledSources.contains(source);
    enabled ? disabledSources.remove(source) : disabledSources.add(source);
    notifyListeners();
    try {
      await _persist();
    } catch (_) {
      wasDisabled
          ? disabledSources.add(source)
          : disabledSources.remove(source);
      notifyListeners();
      rethrow;
    }
  }

  SharedPreferences? _preferences;
  Future<void>? _loading;
  Future<void> _writes = Future.value();
  Future<bool> Function(ProgrammeEntry entry, bool appOnly)? launch;
  Future<ImageProvider?> Function(ProgrammeEntry entry)? loadArtwork;
  Future<void> ready() => _loading ??= _load();
  Future<void> _load() async {
    _preferences = await SharedPreferences.getInstance();
    disabledSources.addAll(
      _preferences!.getStringList('programme_disabled_sources_v1') ?? [],
    );
    hidden.addAll(_preferences!.getStringList('programme_hidden_v1') ?? []);
    for (final value
        in _preferences!.getStringList('programme_watchlist_v1') ?? []) {
      try {
        final entry = ProgrammeEntry.fromMap(
          jsonDecode(value) as Map<String, dynamic>,
        );
        saved[entry.key] = entry;
      } catch (_) {
        /* Skip malformed entries, preserve the remaining list. */
      }
    }
    for (final entry in source) {
      if (saved.containsKey(entry.key)) saved[entry.key] = entry;
    }
    notifyListeners();
  }

  void replace(List<ProgrammeEntry> entries) {
    sourceError = null;
    source = List.unmodifiable(entries);
    // Keep current progress and refreshed deep links for saved programmes.
    for (final entry in entries) {
      if (saved.containsKey(entry.key)) saved[entry.key] = entry;
    }
    notifyListeners();
  }

  List<ProgrammeEntry> get visible =>
      source.where((e) => !hidden.contains(e.key)).toList();
  List<ProgrammeEntry> search(String query) {
    final term = query.trim().toLowerCase();
    final unique = {
      for (final e in [...source, ...saved.values]) e.key: e,
    };
    return unique.values
        .where(
          (e) =>
              !hidden.contains(e.key) &&
              '${e.item.title} ${e.provider} ${e.item.description ?? ""}'
                  .toLowerCase()
                  .contains(term),
        )
        .toList();
  }

  Future<void> setHidden(ProgrammeEntry entry, bool value) async {
    await ready();
    final previous = hidden.contains(entry.key);
    value ? hidden.add(entry.key) : hidden.remove(entry.key);
    notifyListeners();
    try {
      await _persist();
    } catch (_) {
      previous ? hidden.add(entry.key) : hidden.remove(entry.key);
      notifyListeners();
      rethrow;
    }
  }

  Future<void> restoreHidden(String key) async {
    await ready();
    final previous = hidden.contains(key);
    hidden.remove(key);
    notifyListeners();
    try {
      await _persist();
    } catch (_) {
      if (previous) hidden.add(key);
      notifyListeners();
      rethrow;
    }
  }

  Future<void> toggleSaved(ProgrammeEntry entry) async {
    await ready();
    final previous = saved[entry.key];
    saved.containsKey(entry.key)
        ? saved.remove(entry.key)
        : saved[entry.key] = entry;
    notifyListeners();
    try {
      await _persist();
    } catch (_) {
      if (previous == null) {
        saved.remove(entry.key);
      } else {
        saved[entry.key] = previous;
      }
      notifyListeners();
      rethrow;
    }
  }

  Future<void> _persist() {
    final hiddenValues = hidden.toList();
    final disabledValues = disabledSources.toList();
    final savedValues = saved.values.map((e) => jsonEncode(e.toMap())).toList();
    return _writes = _writes.catchError((_) {}).then((_) async {
      if (!await _preferences!.setStringList(
        'programme_disabled_sources_v1',
        disabledValues,
      )) {
        throw StateError('Could not save source preferences');
      }
      if (!await _preferences!.setStringList(
            'programme_hidden_v1',
            hiddenValues,
          ) ||
          !await _preferences!.setStringList(
            'programme_watchlist_v1',
            savedValues,
          )) {
        throw StateError('Could not save programme preferences');
      }
    });
  }
}
