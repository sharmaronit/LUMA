import 'dart:convert';
import 'dart:typed_data';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> saveAppArtwork(String id, Uint8List bytes) async {
  final prefs = await SharedPreferences.getInstance();
  if (!await prefs.setString('app_artwork_data_$id', base64Encode(bytes))) {
    throw StateError('Could not save artwork');
  }
}

Future<Uint8List?> readAppArtwork(String id) async {
  final value = (await SharedPreferences.getInstance()).getString(
    'app_artwork_data_$id',
  );
  return value == null ? null : base64Decode(value);
}

Future<void> deleteAppArtwork(String id) async {
  await (await SharedPreferences.getInstance()).remove('app_artwork_data_$id');
}
