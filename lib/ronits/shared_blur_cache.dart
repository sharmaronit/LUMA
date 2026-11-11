import 'dart:ui' as ui;

/// Wallpaper-scoped ownership. Consumers receive clones, so evictions are safe.
class SharedBlurCache {
  SharedBlurCache({this.capacity = 3});
  final int capacity;
  final _entries = <Object, _BlurEntry>{};
  bool _disposed = false;
  int get entryCount => _entries.length;
  Future<ui.Image> acquire(
    Object key,
    Future<ui.Image> Function() build,
  ) async {
    if (_disposed) throw StateError('Blur cache disposed');
    var entry = _entries.remove(key);
    if (entry == null) {
      entry = _BlurEntry(Future.sync(build));
    }
    _entries[key] = entry;
    while (_entries.length > capacity) {
      _evict(_entries.keys.first);
    }
    ui.Image image;
    try {
      image = await entry.image;
    } catch (_) {
      if (identical(_entries[key], entry)) _entries.remove(key);
      rethrow;
    }
    if (!entry.valid) throw StateError('Blur request superseded');
    return image.clone();
  }

  void _evict(Object key) {
    final entry = _entries.remove(key);
    if (entry == null) return;
    entry.valid = false;
    entry.image.then(
      (image) => image.dispose(),
      onError: (Object _, StackTrace _) {},
    );
  }

  void clear() {
    for (final key in _entries.keys.toList()) {
      _evict(key);
    }
  }

  void dispose() {
    clear();
    _disposed = true;
  }
}

class _BlurEntry {
  _BlurEntry(this.image);
  final Future<ui.Image> image;
  bool valid = true;
}
