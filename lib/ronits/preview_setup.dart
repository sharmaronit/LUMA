import 'package:shared_preferences/shared_preferences.dart';

const restoredPreviewRevision = 'three-themes-20261019';

/// Browser-only design migration. Later appearance choices remain editable.
Future<void> prepareRestoredPreview(SharedPreferences preferences) async {
  if (preferences.getString('preview_design_revision') ==
      restoredPreviewRevision)
    return;
  await preferences.setString('minimal_background', 'glass');
  await preferences.setString('home_card_size', 'medium');
  await preferences.setBool('home_selected_library', false);
  await preferences.setDouble('home_library_offset', 0);
  await preferences.setString(
    'preview_design_revision',
    restoredPreviewRevision,
  );
}
