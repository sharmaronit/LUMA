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

import 'dart:io';
import 'package:flutter/services.dart';
import '../ronits/scenery_wallpapers.dart';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import '../ronits/shared_blur_cache.dart';

import 'package:luma/luma_channel.dart';
import 'package:luma/gradients.dart';
import 'package:luma/providers/settings_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:path_provider/path_provider.dart';

class WallpaperService extends ChangeNotifier {
  final sharedBlurCache = SharedBlurCache();
  final SettingsService _settingsService;
  final LumaChannel _channel = LumaChannel();

  late File _wallpaperFile;
  late File _wallpaperDayFile;
  late File _wallpaperNightFile;
  late File _wallpaperVideoFile;
  late File _wallpaperDayVideoFile;
  late File _wallpaperNightVideoFile;
  bool _initialized = false;
  bool _disposed = false;
  String? _activeVideoPath;
  File? _activeVideoFile;
  Timer? _timer;
  int _wallpaperRevision = 0;

  ImageProvider? _wallpaper;
  bool _explicitGradient = false;
  int get wallpaperRevision => _wallpaperRevision;

  ImageProvider? get wallpaper =>
      _wallpaper ??
      (!_explicitGradient && _settingsService.gradientUuid == null
          ? const AssetImage('assets/mountain.jpg')
          : null);

  /// Resolved once per wallpaper change in [_updateWallpaper]. This getter is
  /// read from several build() methods, so it must not touch the filesystem.
  File? get wallpaperVideoFile => _activeVideoFile;

  LumaGradient get gradient => LumaGradients.all.firstWhere(
    (gradient) => gradient.uuid == _settingsService.gradientUuid,
    orElse: () => LumaGradients.saintPetersburg,
  );

  WallpaperService(this._settingsService) : _wallpaper = null {
    _settingsService.addListener(_onSettingsChanged);
    unawaited(
      _init().catchError((Object error) {
        debugPrint('Wallpaper storage unavailable: $error');
      }),
    );
  }

  bool _lastTimeBasedEnabled = false;

  void _onSettingsChanged() {
    if (!_initialized || _disposed) return;
    final enabled = _settingsService.timeBasedWallpaperEnabled;
    if (enabled != _lastTimeBasedEnabled) {
      _lastTimeBasedEnabled = enabled;
      _updateTimerState();
      _updateWallpaper();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _settingsService.removeListener(_onSettingsChanged);
    _timer?.cancel();
    sharedBlurCache.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final directory = await getApplicationDocumentsDirectory();
    if (_disposed) return;
    _wallpaperFile = File("${directory.path}/wallpaper");
    _wallpaperDayFile = File("${directory.path}/wallpaper_day");
    _wallpaperNightFile = File("${directory.path}/wallpaper_night");
    _wallpaperVideoFile = File("${directory.path}/wallpaper_video");
    _wallpaperDayVideoFile = File("${directory.path}/wallpaper_day_video");
    _wallpaperNightVideoFile = File("${directory.path}/wallpaper_night_video");
    _initialized = true;

    _lastTimeBasedEnabled = _settingsService.timeBasedWallpaperEnabled;
    _updateWallpaper();
    _updateTimerState();
  }

  void _updateTimerState() {
    final enabled = _settingsService.timeBasedWallpaperEnabled;
    if (enabled && (_timer == null || !_timer!.isActive)) {
      _timer = Timer.periodic(
        const Duration(minutes: 1),
        (_) => _updateWallpaper(),
      );
    } else if (!enabled && _timer != null) {
      _timer?.cancel();
      _timer = null;
    }
  }

  File? _resolveActiveVideoFile() {
    if (!isInitialized) return null;

    final now = DateTime.now();
    final isDay = now.hour >= 6 && now.hour < 18;
    final enabled = _settingsService.timeBasedWallpaperEnabled;

    if (enabled) {
      if (isDay && _wallpaperDayVideoFile.existsSync()) {
        return _wallpaperDayVideoFile;
      }
      if (!isDay && _wallpaperNightVideoFile.existsSync()) {
        return _wallpaperNightVideoFile;
      }
      if (_wallpaperVideoFile.existsSync()) {
        return _wallpaperVideoFile;
      }
    } else if (_wallpaperVideoFile.existsSync()) {
      return _wallpaperVideoFile;
    }
    return null;
  }

  bool get isInitialized => _initialized;

  void _updateWallpaper({bool force = false}) {
    if (!_initialized || _disposed) return;
    final now = DateTime.now();
    final isDay = now.hour >= 6 && now.hour < 18;
    final enabled = _settingsService.timeBasedWallpaperEnabled;

    final videoFile = _resolveActiveVideoFile();

    ImageProvider? newWallpaper;

    if (videoFile != null) {
      newWallpaper = null;
    } else if (enabled) {
      if (isDay && _wallpaperDayFile.existsSync()) {
        newWallpaper = FileImage(_wallpaperDayFile);
      } else if (!isDay && _wallpaperNightFile.existsSync()) {
        newWallpaper = FileImage(_wallpaperNightFile);
      } else if (_wallpaperFile.existsSync()) {
        newWallpaper = FileImage(_wallpaperFile); // Fallback
      }
    } else if (_wallpaperFile.existsSync()) {
      newWallpaper = FileImage(_wallpaperFile);
    }

    if (_wallpaper != newWallpaper ||
        _activeVideoPath != videoFile?.path ||
        force) {
      _wallpaper = newWallpaper;
      _activeVideoPath = videoFile?.path;
      _activeVideoFile = videoFile;
      _wallpaperRevision++;
      sharedBlurCache.clear();
      notifyListeners();
    }
  }

  Future<void> pickWallpaper(File sourceFile) async {
    await _saveImage(sourceFile, _wallpaperFile);
  }

  Future<void> pickWallpaperFromUri(String sourceUri) async {
    await _saveImageBytes(
      await _channel.loadContentUriImage(sourceUri),
      _wallpaperFile,
    );
  }

  Future<void> pickWallpaperDay(File sourceFile) async {
    await _saveImage(sourceFile, _wallpaperDayFile);
  }

  Future<void> pickWallpaperDayFromUri(String sourceUri) async {
    await _saveImageBytes(
      await _channel.loadContentUriImage(sourceUri),
      _wallpaperDayFile,
    );
  }

  Future<void> pickWallpaperNight(File sourceFile) async {
    await _saveImage(sourceFile, _wallpaperNightFile);
  }

  Future<void> pickWallpaperNightFromUri(String sourceUri) async {
    await _saveImageBytes(
      await _channel.loadContentUriImage(sourceUri),
      _wallpaperNightFile,
    );
  }

  Future<void> pickVideoWallpaper(File sourceFile) async {
    await _saveVideo(sourceFile, _wallpaperVideoFile);
  }

  Future<void> pickVideoWallpaperDay(File sourceFile) async {
    await _saveVideo(sourceFile, _wallpaperDayVideoFile);
  }

  Future<void> pickVideoWallpaperNight(File sourceFile) async {
    await _saveVideo(sourceFile, _wallpaperNightVideoFile);
  }

  Future<void> pickVideoWallpaperFromUri(String uri, {String? period}) async {
    if (!_initialized || _disposed)
      throw StateError('Wallpaper service is not available');
    final target = period == 'day'
        ? _wallpaperDayVideoFile
        : period == 'night'
        ? _wallpaperNightVideoFile
        : _wallpaperVideoFile;
    await _replaceFile(
      target,
      (temporary) => _channel.copyContentUriToFile(uri, temporary.path),
    );
    await _finishVideoWallpaper(target);
  }

  Future<void> setSceneryWallpaper(String asset) async {
    if (!sceneryWallpapers.any((photo) => photo.asset == asset)) {
      throw ArgumentError.value(asset, 'asset', 'Unknown scenery wallpaper');
    }
    if (!_initialized) throw StateError('Wallpaper service is still loading');
    final data = await rootBundle.load(asset);
    await _settingsService.setTimeBasedWallpaperEnabled(false);
    await _saveImageBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      _wallpaperFile,
    );
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('wallpaper_selected_asset', asset);
  }

  Future<void> _saveImage(File sourceFile, File targetFile) async {
    await _replaceFile(targetFile, (temporary) async {
      await sourceFile.openRead().pipe(temporary.openWrite());
    });
    await _replacePairedVideo(targetFile);
    await _refreshImageWallpaper(targetFile);
  }

  Future<void> _saveImageBytes(Uint8List imageBytes, File targetFile) async {
    if (imageBytes.isEmpty) {
      throw StateError('Unable to read the selected image');
    }

    await _replaceFile(targetFile, (temporary) async {
      await temporary.writeAsBytes(imageBytes, flush: true);
    });
    await _replacePairedVideo(targetFile);

    await _refreshImageWallpaper(targetFile);
  }

  Future<void> _replacePairedVideo(File targetFile) async {
    // Setting an image means the user no longer wants a video wallpaper, so
    // remove all video wallpaper files (including unrelated ones like the
    // general wallpaper_video when setting wallpaper_day) to prevent stale
    // video playback after switching.
    await cleanVideoWallpaperFiles();
  }

  Future<void> _refreshImageWallpaper(File targetFile) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove('wallpaper_selected_asset');
    await preferences.setString('minimal_last_background', 'wallpaper');
    if (!['glass', 'glass-real']
        .contains(_settingsService.selectedMinimalBackground))
      await _settingsService.setMinimalBackground('wallpaper');
    await FileImage(targetFile).evict();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();

    _updateWallpaper(force: true);
  }

  Future<void> _saveVideo(File sourceFile, File targetVideoFile) async {
    await _replaceFile(targetVideoFile, (temporary) async {
      await sourceFile.openRead().pipe(temporary.openWrite());
    });
    await _finishVideoWallpaper(targetVideoFile);
  }

  Future<void> _finishVideoWallpaper(File targetVideoFile) async {
    final pairedImage = _pairedImageForVideo(targetVideoFile);
    if (pairedImage != null && await pairedImage.exists()) {
      await pairedImage.delete();
    }

    _updateWallpaper(force: true);
  }

  Future<void> _replaceFile(
    File target,
    Future<void> Function(File) write,
  ) async {
    if (!_initialized || _disposed) {
      throw StateError('Wallpaper service is not available');
    }
    final temporary = File(
      '${target.path}.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    try {
      await write(temporary);
      if (await temporary.length() == 0) {
        throw StateError('The selected media is empty');
      }
      await temporary.rename(target.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  File? _pairedImageForVideo(File videoFile) {
    if (videoFile.path == _wallpaperVideoFile.path) return _wallpaperFile;
    if (videoFile.path == _wallpaperDayVideoFile.path) return _wallpaperDayFile;
    if (videoFile.path == _wallpaperNightVideoFile.path)
      return _wallpaperNightFile;
    return null;
  }

  Future<void> setGradient(LumaGradient lumaGradient) async {
    _explicitGradient = true;
    await cleanImageWallpaperFiles();
    await cleanVideoWallpaperFiles();

    await _settingsService.setGradientUuid(lumaGradient.uuid);
    // Drop the in-memory wallpaper provider so the gradient is shown instead of
    // the (now deleted) image/video file. _updateWallpaper notifies listeners.
    _updateWallpaper(force: true);
  }

  // Per-profile copies of the wallpaper picture.

  File _profileFile(String id) =>
      File('${_wallpaperFile.parent.path}/wallpaper_profile_$id');

  Future<void> saveProfileWallpaper(String id) async {
    if (!_initialized) return;
    if (await _wallpaperFile.exists()) {
      await _wallpaperFile.copy(_profileFile(id).path);
    } else if (await _profileFile(id).exists()) {
      await _profileFile(id).delete();
    }
  }

  Future<void> restoreProfileWallpaper(String id) async {
    if (!_initialized) return;
    final copy = _profileFile(id);
    if (await copy.exists()) {
      await _replaceFile(_wallpaperFile, (temporary) async {
        await copy.copy(temporary.path);
      });
    }
    await FileImage(_wallpaperFile).evict();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    _updateWallpaper(force: true);
  }

  Future<void> deleteProfileWallpaper(String id) async {
    if (!_initialized) return;
    if (await _profileFile(id).exists()) await _profileFile(id).delete();
  }

  // Cleaning methods

  Future<void> cleanVideoWallpaperFiles() async {
    if (await _wallpaperVideoFile.exists()) {
      await _wallpaperVideoFile.delete();
    }

    if (await _wallpaperDayVideoFile.exists()) {
      await _wallpaperDayVideoFile.delete();
    }

    if (await _wallpaperNightVideoFile.exists()) {
      await _wallpaperNightVideoFile.delete();
    }
  }

  Future<void> cleanImageWallpaperFiles() async {
    if (await _wallpaperFile.exists()) {
      await _wallpaperFile.delete();
    }

    if (await _wallpaperDayFile.exists()) {
      await _wallpaperDayFile.delete();
    }

    if (await _wallpaperNightFile.exists()) {
      await _wallpaperNightFile.delete();
    }
  }
}
