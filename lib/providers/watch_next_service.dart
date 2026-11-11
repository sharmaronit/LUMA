/*
 * FLauncher
 * Copyright (C) 2021 Étienne Fesser
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import 'dart:async';
import 'dart:collection';
import 'dart:typed_data' show BytesBuilder;
import 'package:flutter/painting.dart';
import '../ronits/programme_library.dart';

import 'package:flutter/foundation.dart';
import 'package:luma/luma_channel.dart';
import 'package:luma/models/watch_next_item.dart';
import 'package:http/http.dart' as http;

class WatchNextService extends ChangeNotifier {
  final LumaChannel _lumaChannel;

  List<WatchNextItem> _items = [];
  bool _isLoading = false;
  bool _disposed = false;
  Future<void>? _refreshTask;
  final http.Client _httpClient = http.Client();
  final Queue<Completer<void>> _posterWaiters = Queue();
  int _activePosterLoads = 0;
  int _posterBytes = 0;
  static const _maxPosterBytes = 8 * 1024 * 1024;
  static const _maxCacheBytes = 16 * 1024 * 1024;
  bool _hasPermission = false;
  final Map<String, Uint8List> _posterCache = {};
  final Set<String> _loadingPosters = {};
  final Map<String, Future<void>> _posterTasks = {};
  final Set<String> _failedPosters = {};
  Timer? _refreshTimer;
  Timer? _posterNotifyDebounce;
  static const int _maxParallelPosterLoads = 2;
  late final Future<bool> Function(ProgrammeEntry, bool) _launchDelegate;
  late final Future<ImageProvider?> Function(ProgrammeEntry) _artworkDelegate;

  List<WatchNextItem> get items => List.unmodifiable(_items);
  bool get isLoading => _isLoading;
  bool get hasPermission => _hasPermission;
  bool get hasItems => _items.isNotEmpty;
  bool get hasVisibleSection =>
      !_isLoading && (!_hasPermission || _items.isNotEmpty);

  WatchNextService(this._lumaChannel) {
    ProgrammeLibrary.shared.launch = _launchDelegate = (entry, appOnly) =>
        launchItem(
          appOnly
              ? WatchNextItem(
                  id: entry.item.id,
                  title: entry.item.title,
                  packageName: entry.item.packageName,
                )
              : entry.item,
        );
    ProgrammeLibrary.shared.loadArtwork = _artworkDelegate = (entry) async {
      for (final uri in {entry.item.backdropUri, entry.item.posterUri}) {
        if (uri == null || uri.isEmpty) continue;
        await _loadPosterImage(uri);
        final bytes = getCachedPoster(uri);
        if (bytes != null) return MemoryImage(bytes);
      }
      return null;
    };
    unawaited(ProgrammeLibrary.shared.ready());
    _init();
  }

  Future<void> _refreshInBackground() async {
    try {
      await refreshPermissionAndItems();
    } catch (error) {
      debugPrint('WatchNext: refresh unavailable: $error');
    }
  }

  void _init() async {
    await _refreshInBackground();
    if (_disposed) return;
    _refreshTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      unawaited(_refreshInBackground());
    });
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    if (identical(ProgrammeLibrary.shared.launch, _launchDelegate)) {
      ProgrammeLibrary.shared.launch = null;
      ProgrammeLibrary.shared.setRefreshing(false);
    }
    if (identical(ProgrammeLibrary.shared.loadArtwork, _artworkDelegate)) {
      ProgrammeLibrary.shared.loadArtwork = null;
    }
    _httpClient.close();
    for (final waiter in _posterWaiters) {
      waiter.complete();
    }
    _posterWaiters.clear();
    _posterCache.clear();
    _refreshTimer?.cancel();
    _posterNotifyDebounce?.cancel();
    super.dispose();
  }

  Future<void> checkPermission() async {
    try {
      _hasPermission = await _lumaChannel.checkWatchNextPermission();
    } catch (e) {
      debugPrint('WatchNext: Error checking permission: $e');
      if (!_disposed)
        ProgrammeLibrary.shared.setSourceError(
          'Could not check TV content access. Open App sources and try Refresh.',
        );
      rethrow;
    }
    notifyListeners();
  }

  Future<void> requestPermission() async {
    try {
      await _lumaChannel.requestWatchNextPermission();
    } catch (e) {
      debugPrint('WatchNext: Error requesting permission: $e');
    }
  }

  Future<void> refreshPermissionAndItems() {
    if (_disposed) return Future.value();
    return _refreshTask ??= _refreshPermissionAndItems().whenComplete(() {
      _refreshTask = null;
    });
  }

  Future<void> _refreshPermissionAndItems() async {
    await checkPermission();
    if (_disposed) return;
    if (_hasPermission) {
      await refreshItems();
    } else {
      _items = [];
      ProgrammeLibrary.shared.replace([]);
      notifyListeners();
    }
  }

  Future<void> refreshItems() async {
    if (_isLoading || _disposed) return;

    if (!_hasPermission) {
      await checkPermission();
      if (_disposed) return;
      if (!_hasPermission) {
        _items = [];
        notifyListeners();
        return;
      }
    }

    _failedPosters.clear();
    _isLoading = true;
    ProgrammeLibrary.shared.setRefreshing(true);
    notifyListeners();

    try {
      final results = await _lumaChannel.getWatchNextItems();
      if (_disposed) return;
      _items = results.map((map) => WatchNextItem.fromMap(map)).toList();

      ProgrammeLibrary.shared.replace([
        for (final item in _items)
          ProgrammeEntry(item, item.packageName ?? 'Streaming app'),
      ]);
      unawaited(_preloadInitialPosters());
    } catch (e) {
      debugPrint('WatchNext: Error loading items: $e');
      if (!_disposed)
        ProgrammeLibrary.shared.setSourceError(
          'Could not refresh programmes. Open App sources and try Refresh.',
        );
      rethrow;
    } finally {
      _isLoading = false;
      if (!_disposed) ProgrammeLibrary.shared.setRefreshing(false);
      notifyListeners();
    }
  }

  Future<void> _preloadInitialPosters() async {
    final pendingUris = _items
        .take(3)
        .map((item) => item.posterUri)
        .whereType<String>()
        .where((uri) => !_posterCache.containsKey(uri))
        .toList(growable: false);

    if (pendingUris.isEmpty) {
      return;
    }

    int nextIndex = 0;
    Future<void> worker() async {
      while (nextIndex < pendingUris.length) {
        final uri = pendingUris[nextIndex++];
        await _loadPosterImage(uri);
      }
    }

    final workers = List.generate(_maxParallelPosterLoads, (_) => worker());
    await Future.wait(workers);
  }

  void ensurePosterLoaded(String? uri) {
    if (_disposed ||
        uri == null ||
        _posterCache.containsKey(uri) ||
        _failedPosters.contains(uri) ||
        _loadingPosters.contains(uri)) {
      return;
    }
    unawaited(_loadPosterImage(uri));
  }

  Future<void> _loadPosterImage(String uri) => _posterTasks.putIfAbsent(
    uri,
    () => _fetchPosterImage(uri).whenComplete(() {
      _posterTasks.remove(uri);
    }),
  );

  Future<void> _fetchPosterImage(String uri) async {
    if (_disposed ||
        _posterCache.containsKey(uri) ||
        _loadingPosters.contains(uri)) {
      return;
    }
    _loadingPosters.add(uri);
    if (_activePosterLoads >= _maxParallelPosterLoads) {
      final waiter = Completer<void>();
      _posterWaiters.add(waiter);
      await waiter.future;
    } else {
      _activePosterLoads++;
    }
    try {
      if (_disposed) return;
      Uint8List? imageBytes;

      if (uri.startsWith('content://')) {
        imageBytes = await _lumaChannel.loadContentUriImage(uri);
      } else {
        final uriObj = Uri.parse(uri);
        if (uriObj.scheme != 'https' && uriObj.scheme != 'http') {
          throw const FormatException('Unsupported artwork URL');
        }
        final response = await _httpClient
            .send(http.Request('GET', uriObj))
            .timeout(const Duration(seconds: 10));
        if (response.statusCode == 200) {
          if ((response.contentLength ?? 0) > _maxPosterBytes) {
            throw const FormatException('Artwork exceeds 8 MB');
          }
          imageBytes = await (() async {
            final builder = BytesBuilder(copy: false);
            await for (final chunk in response.stream) {
              if (builder.length + chunk.length > _maxPosterBytes) {
                throw const FormatException('Artwork exceeds 8 MB');
              }
              builder.add(chunk);
            }
            return builder.takeBytes();
          })().timeout(const Duration(seconds: 10));
        } else {
          await response.stream.listen((_) {}).cancel();
        }
      }

      if (_disposed) return;
      if (imageBytes != null &&
          imageBytes.isNotEmpty &&
          imageBytes.length <= _maxPosterBytes) {
        while (_posterCache.isNotEmpty &&
            (_posterBytes + imageBytes.length > _maxCacheBytes ||
                _posterCache.length >= 48)) {
          _posterBytes -= _posterCache.remove(_posterCache.keys.first)!.length;
        }
        _posterCache[uri] = imageBytes;
        _posterBytes += imageBytes.length;
        _failedPosters.remove(uri);
        _schedulePosterCacheNotification();
      } else {
        _failedPosters.add(uri);
        _schedulePosterCacheNotification();
      }
    } catch (_) {
      _failedPosters.add(uri);
      _schedulePosterCacheNotification();
    } finally {
      _loadingPosters.remove(uri);
      if (_posterWaiters.isNotEmpty) {
        _posterWaiters.removeFirst().complete();
      } else {
        _activePosterLoads--;
      }
    }
  }

  void _schedulePosterCacheNotification() {
    if (_disposed || (_posterNotifyDebounce?.isActive ?? false)) {
      return;
    }
    _posterNotifyDebounce = Timer(
      const Duration(milliseconds: 80),
      notifyListeners,
    );
  }

  Uint8List? getCachedPoster(String? uri) {
    if (uri == null) return null;
    final bytes = _posterCache.remove(uri);
    if (bytes != null) _posterCache[uri] = bytes;
    return bytes;
  }

  bool hasPosterLoadFailed(String? uri) {
    if (uri == null) return false;
    return _failedPosters.contains(uri);
  }

  Future<bool> launchItem(WatchNextItem item) async {
    debugPrint('WatchNext: Launching item: ${item.title}');
    debugPrint(
      'WatchNext: packageName=${item.packageName}, contentId=${item.contentId}, intentUri=${item.intentUri}',
    );

    if (item.packageName == null && item.intentUri == null) {
      debugPrint('WatchNext: Cannot launch - no package name or intent URI');
      return false;
    }

    return _lumaChannel.launchWatchNextItem(
      item.packageName,
      item.contentId,
      item.intentUri,
    );
  }
}
