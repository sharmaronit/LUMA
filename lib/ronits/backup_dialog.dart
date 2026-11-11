import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'launcher_backup.dart';
import 'motion.dart';
import 'focus_feedback.dart';
import 'glass_surface.dart';

Future<void> showBackupDialog(
  BuildContext context, {
  LauncherMaterial mode = LauncherMaterial.solid,
  GlassBlurBuilder? blurBuilder,
  required Future<String> Function() export,
  required Future<void> Function(LauncherBackup) restore,
  Future<String?> Function()? readLocal,
  Future<String> Function(String)? saveLocal,
  Future<String?> Function()? readFile,
  Future<bool> Function(String)? writeFile,
}) => showLumaDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _BackupDialog(
    mode: mode,
    blurBuilder: blurBuilder,
    export: export,
    restore: restore,
    readLocal: readLocal,
    saveLocal: saveLocal,
    readFile: readFile,
    writeFile: writeFile,
  ),
);

class _BackupDialog extends StatefulWidget {
  const _BackupDialog({
    required this.mode,
    this.blurBuilder,
    required this.export,
    required this.restore,
    this.readLocal,
    this.saveLocal,
    this.readFile,
    this.writeFile,
  });
  final LauncherMaterial mode;
  final GlassBlurBuilder? blurBuilder;
  final Future<String> Function() export;
  final Future<void> Function(LauncherBackup) restore;
  final Future<String?> Function()? readLocal, readFile;
  final Future<String> Function(String)? saveLocal;
  final Future<bool> Function(String)? writeFile;
  @override
  State<_BackupDialog> createState() => _BackupDialogState();
}

class _BackupDialogState extends State<_BackupDialog> {
  final text = TextEditingController();
  String message =
      'Backs up appearance, clock, collections, favourites and hidden apps. Photo/video files and APKs are not included.';
  bool busy = false;
  bool showJson = false;
  LauncherBackup? candidate;
  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await action();
    } catch (error) {
      if (mounted)
        setState(() {
          candidate = null;
          message = 'Backup operation failed: $error';
        });
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void review(String value) {
    final parsed = LauncherBackup.parse(value);
    setState(() {
      text.text = value;
      candidate = parsed;
      message =
          '${parsed.summary}\nRestore replaces saved preferences and app collections. Missing apps are skipped. Review, then select Apply restore.';
    });
  }

  Widget action(
    String title,
    Future<void> Function() callback, {
    bool autofocus = false,
  }) => TvMenuRow(
    key: ValueKey(title),
    title: title,
    autofocus: autofocus,
    onPressed: () {
      if (!busy) run(callback);
    },
  );
  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: Colors.transparent,
    child: SizedBox(
      width: 620,
      height: 460,
      child: GlassSurface(
        mode: widget.mode,
        sheet: true,
        frostedSheet: true,
        blurBuilder: widget.blurBuilder,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Backup & restore',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close backup',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            if (busy) const LinearProgressIndicator(),
            Expanded(
              child: FocusHighlightLayer(
                menu: true,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        message,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.white70,
                        ),
                      ),
                    ),
                    if (candidate != null)
                      action('Apply restore', () async {
                        await widget.restore(candidate!);
                        if (mounted)
                          setState(() {
                            candidate = null;
                            message =
                                'Restore complete. Preferences and available app collections restored.';
                          });
                      }),
                    if (widget.saveLocal != null)
                      action('Save local backup', () async {
                        final result = await widget.saveLocal!(
                          await widget.export(),
                        );
                        if (mounted) setState(() => message = result);
                      }, autofocus: true),
                    if (widget.readLocal != null)
                      action('Load local backup', () async {
                        final value = await widget.readLocal!();
                        if (value != null && mounted) review(value);
                      }),
                    action('Copy backup', () async {
                      await Clipboard.setData(
                        ClipboardData(text: await widget.export()),
                      );
                      if (mounted)
                        setState(
                          () => message =
                              'Backup copied. Save the JSON in a text file.',
                        );
                    }, autofocus: widget.saveLocal == null),
                    if (widget.writeFile != null)
                      action('Export file', () async {
                        final saved = await widget.writeFile!(
                          await widget.export(),
                        );
                        if (mounted)
                          setState(
                            () => message = saved
                                ? 'Backup file saved.'
                                : 'Export cancelled.',
                          );
                      }),
                    if (widget.readFile != null)
                      action('Open backup', () async {
                        final value = await widget.readFile!();
                        if (value != null && mounted) review(value);
                      }),
                    TvMenuRow(
                      key: const ValueKey('edit-json'),
                      title: showJson
                          ? 'Hide JSON editor'
                          : 'Enter backup JSON',
                      subtitle: 'Paste a backup, then review before applying',
                      onPressed: () => setState(() => showJson = !showJson),
                    ),
                    if (showJson) ...[
                      action('Paste backup', () async {
                        final value = (await Clipboard.getData(
                          Clipboard.kTextPlain,
                        ))?.text;
                        if (!mounted) return;
                        setState(() {
                          candidate = null;
                          if (value == null || value.isEmpty) {
                            message =
                                'The clipboard is empty. Copy a backup first.';
                          } else {
                            text.text = value;
                            message =
                                'Backup pasted. Select Review JSON before applying.';
                          }
                        });
                      }),
                      TextField(
                        controller: text,
                        minLines: 3,
                        maxLines: 5,
                        maxLength: 1024 * 1024,
                        decoration: const InputDecoration(
                          labelText: 'Backup JSON',
                        ),
                        onChanged: (_) => setState(() => candidate = null),
                      ),
                      action('Review JSON', () async {
                        review(text.text);
                      }),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
