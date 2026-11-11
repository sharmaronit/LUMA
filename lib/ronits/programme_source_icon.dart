import 'package:flutter/material.dart';
import 'programme_library.dart';
import 'tv_icon_pack.dart';

class ProgrammeSourceIcon extends StatefulWidget {
  const ProgrammeSourceIcon({
    super.key,
    required this.source,
    required this.name,
  });
  final String source, name;
  @override
  State<ProgrammeSourceIcon> createState() => _ProgrammeSourceIconState();
}

class _ProgrammeSourceIconState extends State<ProgrammeSourceIcon> {
  late Future<ImageProvider?> image;
  void load() {
    final packed = tvIconPackArtwork(widget.source, widget.name);
    image = packed != null
        ? Future.value(packed)
        : ProgrammeLibrary.shared.loadAppIcon?.call(widget.source) ??
              Future.value(null);
  }

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void didUpdateWidget(ProgrammeSourceIcon old) {
    super.didUpdateWidget(old);
    if (old.source != widget.source || old.name != widget.name) load();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 36,
    height: 23,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: FutureBuilder<ImageProvider?>(
        future: image,
        builder: (_, snapshot) => snapshot.data == null
            ? const Icon(Icons.tv_rounded, size: 20)
            : Image(
                image: ResizeImage(snapshot.data!, width: 96),
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) =>
                    const Icon(Icons.tv_rounded, size: 20),
              ),
      ),
    ),
  );
}
