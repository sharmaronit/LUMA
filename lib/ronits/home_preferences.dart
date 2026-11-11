import 'package:shared_preferences/shared_preferences.dart';

/// Home-only preferences shared by the TV build and browser preview.
class HomePreferences {
  HomePreferences(this.storage);
  final SharedPreferences storage;
  static const sizes = ['small', 'medium', 'large'];
  static const rows = ['watch', 'recent'];
  String get size {
    final value = storage.getString('home_card_size');
    return sizes.contains(value) ? value! : 'medium';
  }

  bool get accent => storage.getBool('home_wallpaper_accent') ?? true;
  bool get remember => storage.getBool('home_remember_selection') ?? true;
  List<String> get order {
    final saved = storage.getStringList('home_row_order') ?? rows;
    return [
      ...saved.where(rows.contains).toSet(),
      ...rows.where((r) => !saved.contains(r)),
    ];
  }

  bool visible(String row) =>
      storage.getBool('home_show_$row') ?? (row == 'watch');
  String? get selected => storage.getString('home_selected_app');
  bool get library => storage.getBool('home_selected_library') ?? false;
  double get offset => storage.getDouble('home_library_offset') ?? 0;
  Future<void> saveSelection(String id, bool library, double offset) async {
    if (!remember) return;
    await storage.setString('home_selected_app', id);
    await storage.setBool('home_selected_library', library);
    await storage.setDouble(
      'home_library_offset',
      offset.isFinite ? offset.clamp(0, double.maxFinite) : 0,
    );
  }
}
