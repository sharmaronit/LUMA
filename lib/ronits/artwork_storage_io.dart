import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';

Future<File> _file(String id) async {
  final root = await getApplicationSupportDirectory();
  final dir = Directory('${root.path}/app-artwork');
  await dir.create(recursive: true);
  return File('${dir.path}/${base64Url.encode(utf8.encode(id))}.png');
}

Future<void> saveAppArtwork(String id, Uint8List bytes) async {
  final file = await _file(id);
  final temp = File('${file.path}.tmp');
  await temp.writeAsBytes(bytes, flush: true);
  await temp.rename(file.path);
}

Future<Uint8List?> readAppArtwork(String id) async {
  final file = await _file(id);
  return await file.exists() ? file.readAsBytes() : null;
}

Future<void> deleteAppArtwork(String id) async {
  final file = await _file(id);
  if (await file.exists()) await file.delete();
}
