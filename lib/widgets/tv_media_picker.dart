import '../ronits/glass_surface.dart';
import '../ronits/motion.dart';

import 'package:luma/luma_channel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum TvMediaPickerMode { image, video }

class TvMediaPicker extends StatefulWidget {
  final TvMediaPickerMode mode;

  const TvMediaPicker({super.key, required this.mode});

  static Future<TvMediaSelection?> show(
    BuildContext context, {
    required TvMediaPickerMode mode,
  }) async {
    final result = await showLumaDialog<TvMediaSelection>(
      context: context,
      barrierDismissible: false,
      builder: (_) => TvMediaPicker(mode: mode),
    );
    return result;
  }

  @override
  State<TvMediaPicker> createState() => _TvMediaPickerState();
}

class _TvMediaPickerState extends State<TvMediaPicker>
    with WidgetsBindingObserver {
  final LumaChannel _channel = LumaChannel();
  List<_MediaItem> _items = [];
  bool _loading = true;
  bool _permissionDenied = false;
  bool _permissionRequestActive = false;
  String? _error;
  int _loadTicket = 0;
  int _selectedIndex = 0;
  final ScrollController _scrollController = ScrollController();
  double _gridRowExtent = 120;

  bool get isImage => widget.mode == TvMediaPickerMode.image;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _requestPermissionAndLoad();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _permissionDenied) {
      _checkPermissionAndLoad();
    }
  }

  Future<void> _checkPermissionAndLoad() async {
    if (_permissionRequestActive || !mounted) return;
    try {
      if (await _channel.checkMediaPermission(isImage ? 'image' : 'video') &&
          mounted) {
        await _loadMedia();
      }
    } catch (_) {
      if (mounted)
        setState(() {
          _loading = false;
          _error = 'Could not check media access. Please try again.';
        });
    }
  }

  Future<void> _requestPermissionAndLoad() async {
    if (_permissionRequestActive || !mounted) return;
    _permissionRequestActive = true;
    setState(() {
      _loading = true;
      _permissionDenied = false;
      _error = null;
    });
    try {
      final type = isImage ? 'image' : 'video';
      var granted = await _channel.checkMediaPermission(type);
      if (!mounted) return;
      if (!granted) {
        await _channel.requestMediaPermission(type);
        if (!mounted) return;
        granted = await _channel.checkMediaPermission(type);
      }
      if (!mounted) return;
      if (!granted) {
        setState(() {
          _loading = false;
          _permissionDenied = true;
        });
        return;
      }
      await _loadMedia();
    } catch (_) {
      if (mounted)
        setState(() {
          _loading = false;
          _error = 'Could not open your media library. Please try again.';
        });
    } finally {
      _permissionRequestActive = false;
    }
  }

  Future<void> _loadMedia() async {
    if (!mounted) return;
    final ticket = ++_loadTicket;
    setState(() {
      _loading = true;
      _permissionDenied = false;
    });
    try {
      final data = isImage
          ? await _channel.getMediaStoreImages()
          : await _channel.getMediaStoreVideos();

      final items = <_MediaItem>[];
      for (final entry in data) {
        final path = entry['path'] as String? ?? '';
        final uri = entry['uri'];
        final id = entry['id'];
        if (uri is String && uri.startsWith('content://') && id is num) {
          items.add(
            _MediaItem(
              id: id.toInt(),
              name: entry['name'] as String? ?? 'Unknown',
              path: path,
              uri: uri,
            ),
          );
        }
      }
      if (mounted && ticket == _loadTicket) {
        setState(() {
          _error = null;
          _items = items;
          _loading = false;
          if (items.isNotEmpty) _selectedIndex = 0;
        });
      }
    } catch (e) {
      if (mounted && ticket == _loadTicket) {
        setState(() {
          _loading = false;
          _error = 'Could not load your media. Please try again.';
        });
      }
    }
  }

  void _select() {
    if (_items.isEmpty) return;
    final item = _items[_selectedIndex];
    Navigator.of(context).pop(TvMediaSelection(uri: item.uri, path: item.path));
  }

  void _moveFocus(int direction) {
    if (_items.isEmpty) return;
    if (direction == -1 && _selectedIndex % 5 == 0) return;
    if (direction == 1 && _selectedIndex % 5 == 4) return;
    int newIndex = _selectedIndex + direction;
    if (newIndex < 0) newIndex = 0;
    if (newIndex >= _items.length) newIndex = _items.length - 1;
    if (newIndex != _selectedIndex) {
      setState(() => _selectedIndex = newIndex);
      _ensureVisible(newIndex);
    }
  }

  void _ensureVisible(int index) {
    if (!_scrollController.hasClients) return;
    final offset = (index ~/ 5) * _gridRowExtent + 24;
    final viewportHeight = _scrollController.position.viewportDimension;
    final currentScroll = _scrollController.offset;

    if (offset < currentScroll) {
      _scrollController.animateTo(
        offset.clamp(0.0, _scrollController.position.maxScrollExtent),
        duration: motionReduced(context)
            ? Duration.zero
            : const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    } else if (offset + _gridRowExtent > currentScroll + viewportHeight) {
      _scrollController.animateTo(
        (offset + _gridRowExtent - viewportHeight).clamp(
          0.0,
          _scrollController.position.maxScrollExtent,
        ),
        duration: motionReduced(context)
            ? Duration.zero
            : const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent)
      return KeyEventResult.ignored;

    // Permission/retry controls use normal focus traversal, not grid movement.
    if (_loading || _permissionDenied || _items.isEmpty)
      return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _moveFocus(1);
      return KeyEventResult.handled;
    } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _moveFocus(-1);
      return KeyEventResult.handled;
    } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _moveFocus(5);
      return KeyEventResult.handled;
    } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _moveFocus(-5);
      return KeyEventResult.handled;
    } else if (event.logicalKey == LogicalKeyboardKey.select ||
        event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.gameButtonA) {
      if (event is KeyDownEvent) _select();
      return KeyEventResult.handled;
    } else if (event.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final title = isImage ? 'Select Image' : 'Select Video';
    final accentColor = Theme.of(context).colorScheme.primary;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(40),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(20)),
      ),
      child: GlassSurface(
        mode: LauncherMaterial.ronits,
        sheet: true,
        child: Focus(
          autofocus: true,
          onKeyEvent: _handleKeyEvent,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(32, 24, 32, 16),
                child: Row(
                  children: [
                    Icon(
                      isImage ? Icons.image : Icons.videocam,
                      color: accentColor,
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      title,
                      style: Theme.of(
                        context,
                      ).textTheme.headlineSmall?.copyWith(color: Colors.white),
                    ),
                    const Spacer(),
                    if (!_permissionDenied && !_loading)
                      Text(
                        '${_items.length} items',
                        style: Theme.of(
                          context,
                        ).textTheme.bodyMedium?.copyWith(color: Colors.white54),
                      ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Colors.white12),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_error!, textAlign: TextAlign.center),
                            const SizedBox(height: 16),
                            TextButton.icon(
                              autofocus: true,
                              onPressed: _requestPermissionAndLoad,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Retry'),
                            ),
                          ],
                        ),
                      )
                    : _permissionDenied
                    ? _buildPermissionDenied(accentColor)
                    : _items.isEmpty
                    ? Center(
                        child: Text(
                          isImage
                              ? 'No images found on device'
                              : 'No videos found on device',
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 16,
                          ),
                        ),
                      )
                    : _buildGrid(),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: Text(
                    _items.isEmpty
                        ? 'D-pad: navigate  •  Back: cancel'
                        : 'D-pad: navigate  •  Select: set wallpaper  •  Back: cancel',
                    style: const TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPermissionDenied(Color accentColor) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.lock_outline, color: Colors.white38, size: 48),
          const SizedBox(height: 16),
          const Text(
            'Media access permission is required',
            style: TextStyle(color: Colors.white54, fontSize: 16),
          ),
          const SizedBox(height: 8),
          const Text(
            'Grant permission to browse photos and videos',
            style: TextStyle(color: Colors.white38, fontSize: 13),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            autofocus: true,
            onPressed: _requestPermissionAndLoad,
            style: ElevatedButton.styleFrom(
              backgroundColor: accentColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            ),
            icon: const Icon(Icons.settings),
            label: const Text('Grant Permission'),
          ),
        ],
      ),
    );
  }

  Widget _buildGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        _gridRowExtent = ((constraints.maxWidth - 48 - 48) / 5) * 9 / 16 + 12;
        return GridView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.all(24),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 5,
            childAspectRatio: 16 / 9,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
          ),
          itemCount: _items.length,
          itemBuilder: (context, index) {
            final item = _items[index];
            final isSelected = index == _selectedIndex;
            return GestureDetector(
              onTap: () {
                _selectedIndex = index;
                _select();
              },
              child: _MediaTile(
                key: ValueKey(item.uri),
                item: item,
                isSelected: isSelected,
                isImage: isImage,
                accentColor: Theme.of(context).colorScheme.primary,
              ),
            );
          },
        );
      },
    );
  }
}

class _MediaItem {
  final int id;
  final String name;
  final String path;
  final String uri;

  _MediaItem({
    required this.id,
    required this.name,
    required this.path,
    required this.uri,
  });
}

class TvMediaSelection {
  final String uri;
  final String path;

  const TvMediaSelection({required this.uri, required this.path});
}

class _MediaTile extends StatelessWidget {
  final _MediaItem item;
  final bool isSelected;
  final bool isImage;
  final Color accentColor;

  const _MediaTile({
    super.key,
    required this.item,
    required this.isSelected,
    required this.isImage,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: motionReduced(context)
          ? Duration.zero
          : const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        border: Border.all(
          color: isSelected ? accentColor : Colors.white12,
          width: isSelected ? 3 : 1,
        ),
      ),
      clipBehavior: Clip.hardEdge,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: isImage
                ? _ImageThumbnail(uri: item.uri)
                : _VideoThumbnail(
                    id: item.id,
                    path: item.path,
                    accentColor: accentColor,
                  ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            color: isSelected
                ? accentColor.withValues(alpha: 0.2)
                : Colors.black45,
            child: Text(
              item.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: isSelected ? Colors.white : Colors.white70,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ImageThumbnail extends StatefulWidget {
  const _ImageThumbnail({required this.uri});
  final String uri;
  @override
  State<_ImageThumbnail> createState() => _ImageThumbnailState();
}

class _ImageThumbnailState extends State<_ImageThumbnail> {
  late final Future<Uint8List?> thumbnail = LumaChannel()
      .getMediaStoreImageThumbnail(widget.uri);
  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List?>(
    future: thumbnail,
    builder: (_, data) => data.data?.isNotEmpty == true
        ? Image.memory(
            data.data!,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) =>
                const Icon(Icons.broken_image_outlined),
          )
        : const ColoredBox(
            color: Colors.black26,
            child: Icon(Icons.image_outlined),
          ),
  );
}

class _VideoThumbnail extends StatefulWidget {
  final int id;
  final String path;
  final Color accentColor;

  const _VideoThumbnail({
    required this.id,
    required this.path,
    required this.accentColor,
  });

  @override
  State<_VideoThumbnail> createState() => _VideoThumbnailState();
}

class _VideoThumbnailState extends State<_VideoThumbnail> {
  late final Future<Uint8List?> _thumb = LumaChannel()
      .getMediaStoreVideoThumbnail(widget.id, path: widget.path);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: _thumb,
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        return Stack(
          fit: StackFit.expand,
          alignment: Alignment.center,
          children: [
            if (bytes != null)
              Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true)
            else
              const ColoredBox(color: Colors.black26),
            if (snapshot.connectionState == ConnectionState.waiting)
              const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              Container(
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                padding: const EdgeInsets.all(8),
                child: const Icon(
                  Icons.play_arrow,
                  color: Colors.white,
                  size: 24,
                ),
              ),
          ],
        );
      },
    );
  }
}
