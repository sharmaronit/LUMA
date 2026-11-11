// Luma
// Copyright (C) 2026 Ronit Sharma
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'focus_feedback.dart';
import 'menu_dialog.dart';
import 'motion.dart';

@immutable
class Profile {
  const Profile(this.id, this.name);
  final String id, name;

  /// One character for the badge. "Person 2" shows 2, so the default names
  /// can be told apart.
  String get initial {
    final numbered = RegExp(r'^Person (\d)$').firstMatch(name.trim());
    if (numbered != null) return numbered.group(1)!;
    return name.trim().isEmpty
        ? '?'
        : name.trim().characters.first.toUpperCase();
  }
}

/// What a profile switch needs from the rest of the app; a fake in tests.
abstract class ProfileHost {
  /// The favourites bar, in order, as package names.
  Future<List<String>> favourites();
  Future<void> setFavourites(List<String> packages);

  /// Keeps and brings back a copy of the wallpaper picture for a profile.
  Future<void> saveWallpaper(String profileId);
  Future<void> restoreWallpaper(String profileId);
  Future<void> deleteWallpaper(String profileId);

  /// Called after the stored settings were swapped.
  void settingsChanged();
}

/// Each person gets their own favourites, wallpaper, theme, clock and font.
///
/// The app always reads and writes the same settings and the same favourites
/// list. A switch saves those under the leaving profile and puts the arriving
/// profile's saved copy in their place, so nothing else in the app has to know
/// about profiles. A new profile starts as a copy of the current one.
class ProfileService extends ChangeNotifier {
  ProfileService(this._prefs, {this.host}) {
    _load();
  }
  final SharedPreferences _prefs;
  ProfileHost? host;

  static const maxProfiles = 6;
  static const _listKey = 'luma_profiles', _activeKey = 'luma_profile_active';

  /// Settings that belong to a person. Everything else is shared by the TV.
  static const personalKeys = [
    'minimal_background',
    'minimal_last_background',
    'solid_theme_color',
    'wallpaper_selected_asset',
    'home_clock_style',
    'home_clock_size',
    'time_format',
    'launcher_font_style',
    'depth_clock',
    'accent_color',
    'gradient_uuid',
    'home_wallpaper_accent',
    'home_card_size',
    'home_row_order',
    'home_show_watch',
    'home_show_recent',
    'home_selected_app',
    'home_selected_library',
    'home_library_offset',
  ];

  var _profiles = const [Profile('p1', 'Person 1')];
  var _active = 'p1';
  var _switching = false;

  /// Goes up on every switch, so the home screen can rebuild from scratch.
  int generation = 0;

  List<Profile> get profiles => List.unmodifiable(_profiles);
  Profile get active =>
      _profiles.firstWhere((p) => p.id == _active, orElse: () => _profiles[0]);
  bool get switching => _switching;
  bool get canAdd => _profiles.length < maxProfiles;

  void _load() {
    try {
      final stored = jsonDecode(_prefs.getString(_listKey) ?? '[]') as List;
      final list = [
        for (final item in stored)
          if (item is Map && item['id'] is String && item['name'] is String)
            Profile(item['id'] as String, item['name'] as String),
      ];
      if (list.isNotEmpty) _profiles = list;
    } catch (_) {
      /* A damaged list falls back to the single default profile. */
    }
    final active = _prefs.getString(_activeKey);
    _active = _profiles.any((p) => p.id == active) ? active! : _profiles[0].id;
  }

  Future<void> _store() async {
    await _prefs.setString(
      _listKey,
      jsonEncode([
        for (final p in _profiles) {'id': p.id, 'name': p.name},
      ]),
    );
    await _prefs.setString(_activeKey, _active);
  }

  static String _clean(String name) {
    final value = name.trim().replaceAll(RegExp(r'\s+'), ' ');
    return value.length > 20 ? value.substring(0, 20) : value;
  }

  /// Adds a person and returns the new profile, or null when the list is full.
  Future<Profile?> add([String? name]) async {
    if (!canAdd) return null;
    var number = _profiles.length + 1;
    while (_profiles.any((p) => p.name == 'Person $number')) {
      number++;
    }
    var id = 1;
    while (_profiles.any((p) => p.id == 'p$id')) {
      id++;
    }
    final cleaned = _clean(name ?? '');
    final profile = Profile(
      'p$id',
      cleaned.isEmpty ? 'Person $number' : cleaned,
    );
    _profiles = [..._profiles, profile];
    await _store();
    notifyListeners();
    return profile;
  }

  Future<void> rename(String id, String name) async {
    final cleaned = _clean(name);
    if (cleaned.isEmpty || !_profiles.any((p) => p.id == id)) return;
    _profiles = [
      for (final p in _profiles) p.id == id ? Profile(id, cleaned) : p,
    ];
    await _store();
    notifyListeners();
  }

  /// Removes a profile and its saved look. The active profile and the last
  /// remaining one cannot be removed.
  Future<bool> remove(String id) async {
    if (id == _active || _profiles.length < 2) return false;
    if (!_profiles.any((p) => p.id == id)) return false;
    _profiles = [
      for (final p in _profiles)
        if (p.id != id) p,
    ];
    await _prefs.remove(_dataKey(id));
    await _prefs.remove(_favouritesKey(id));
    await host?.deleteWallpaper(id);
    await _store();
    notifyListeners();
    return true;
  }

  static String _dataKey(String id) => 'luma_profile_data_$id';
  static String _favouritesKey(String id) => 'luma_profile_favourites_$id';

  Future<void> switchTo(String id) async {
    if (_switching || id == _active || !_profiles.any((p) => p.id == id)) {
      return;
    }
    _switching = true;
    notifyListeners();
    try {
      // Save the leaving profile.
      await _prefs.setString(
        _dataKey(_active),
        jsonEncode({
          for (final key in personalKeys)
            if (_prefs.get(key) != null) key: _prefs.get(key),
        }),
      );
      final host = this.host;
      if (host != null) {
        await _prefs.setStringList(
          _favouritesKey(_active),
          await host.favourites(),
        );
        await host.saveWallpaper(_active);
      }
      // Bring in the arriving one. Without saved data it is new, and simply
      // keeps what is on screen as its starting point.
      final saved = _prefs.getString(_dataKey(id));
      if (saved != null) {
        final data = (jsonDecode(saved) as Map).cast<String, Object?>();
        for (final key in personalKeys) {
          final value = data[key];
          if (value is bool) {
            await _prefs.setBool(key, value);
          } else if (value is int) {
            await _prefs.setInt(key, value);
          } else if (value is double) {
            await _prefs.setDouble(key, value);
          } else if (value is String) {
            await _prefs.setString(key, value);
          } else if (value is List) {
            await _prefs.setStringList(key, [
              for (final item in value) '$item',
            ]);
          } else {
            await _prefs.remove(key);
          }
        }
        final favourites = _prefs.getStringList(_favouritesKey(id));
        if (host != null) {
          if (favourites != null) await host.setFavourites(favourites);
          await host.restoreWallpaper(id);
        }
      }
      _active = id;
      await _store();
      host?.settingsChanged();
    } finally {
      _switching = false;
      generation++;
      notifyListeners();
    }
  }
}

/// Settings > Home & Apps > Profiles: add, rename, remove and switch.
Future<void> showProfilesSettings(
  BuildContext context,
  ProfileService service,
) => showLumaDialog<void>(
  context: context,
  builder: (dialogContext) => ListenableBuilder(
    listenable: service,
    builder: (_, _) => LumaMenuDialog(
      title: const Text('Profiles'),
      content: FocusHighlightLayer(
        menu: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text(
                'Each person gets their own favourites, wallpaper, theme, clock and font. '
                'Apps and their sign-ins are shared by the TV.',
              ),
            ),
            for (final profile in service.profiles)
              TvMenuRow(
                key: ValueKey('profile-${profile.id}'),
                autofocus: profile.id == service.active.id,
                icon: Icons.person_rounded,
                title: profile.name,
                subtitle: profile.id == service.active.id
                    ? 'Watching now'
                    : 'Switch to this person',
                selected: profile.id == service.active.id,
                onPressed: () async {
                  if (profile.id == service.active.id) return;
                  // The whole home rebuilds on a switch, so leave Settings.
                  Navigator.of(
                    dialogContext,
                  ).popUntil((route) => route.isFirst);
                  await service.switchTo(profile.id);
                },
              ),
            if (service.canAdd)
              TvMenuRow(
                key: const ValueKey('profile-add'),
                icon: Icons.person_add_rounded,
                title: 'Add a person',
                subtitle: 'Starts as a copy of ${service.active.name}',
                onPressed: () => service.add(),
              ),
            TvMenuRow(
              key: const ValueKey('profile-rename'),
              icon: Icons.edit_rounded,
              title: 'Rename ${service.active.name}',
              onPressed: () async {
                final name = await _askName(dialogContext, service.active.name);
                if (name != null) {
                  await service.rename(service.active.id, name);
                }
              },
            ),
            for (final profile in service.profiles)
              if (profile.id != service.active.id)
                TvMenuRow(
                  key: ValueKey('profile-remove-${profile.id}'),
                  icon: Icons.person_remove_rounded,
                  title: 'Remove ${profile.name}',
                  subtitle: 'Deletes this person\'s favourites and look',
                  onPressed: () async {
                    if (await _confirmRemove(dialogContext, profile)) {
                      await service.remove(profile.id);
                    }
                  },
                ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Back'),
        ),
      ],
    ),
  ),
);

Future<bool> _confirmRemove(BuildContext context, Profile profile) async =>
    await showLumaDialog<bool>(
      context: context,
      builder: (dialogContext) => LumaMenuDialog(
        title: Text('Remove ${profile.name}?'),
        content: const Text(
          'Their favourites, wallpaper and settings are deleted. Apps stay installed.',
        ),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep'),
          ),
          TextButton(
            key: const ValueKey('profile-remove-confirm'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    ) ??
    false;

Future<String?> _askName(BuildContext context, String current) {
  final controller = TextEditingController(text: current);
  return showLumaDialog<String>(
    context: context,
    builder: (dialogContext) => LumaMenuDialog(
      title: const Text('Name'),
      content: TextField(
        key: const ValueKey('profile-name-field'),
        controller: controller,
        autofocus: true,
        maxLength: 20,
        textInputAction: TextInputAction.done,
        onSubmitted: (value) => Navigator.pop(dialogContext, value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Cancel'),
        ),
        TextButton(
          key: const ValueKey('profile-name-save'),
          onPressed: () => Navigator.pop(dialogContext, controller.text),
          child: const Text('Save'),
        ),
      ],
    ),
  ).whenComplete(controller.dispose);
}
