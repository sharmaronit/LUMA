import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'menu_dialog.dart';

class AppQuickAction {
  const AppQuickAction(this.id, this.label);
  final String id, label;
}

class NativeAppActions {
  static const _channel = MethodChannel('app.luma.tvlauncher/method');
  Future<List<AppQuickAction>> load(String package) async {
    final values = await _channel.invokeListMethod<dynamic>(
      'getAppActions',
      package,
    );
    return [
      for (final value in values ?? [])
        if (value is Map && value['id'] is String && value['label'] is String)
          AppQuickAction(value['id'] as String, value['label'] as String),
    ];
  }

  Future<void> launch(String package, String id, {String? query}) =>
      _channel.invokeMethod<void>('launchAppAction', {
        'package': package,
        'id': id,
        if (query != null) 'query': query,
      });
}

/// Standard Android SEARCH actions receive a query; blank searches never launch.
class AppSearchDialog extends StatefulWidget {
  const AppSearchDialog({super.key, required this.appName});
  final String appName;
  @override
  State<AppSearchDialog> createState() => _AppSearchDialogState();
}

class _AppSearchDialogState extends State<AppSearchDialog> {
  String query = '';
  void submit(String value) {
    final text = value.trim();
    if (text.isNotEmpty) Navigator.pop(context, text);
  }

  @override
  Widget build(BuildContext context) => LumaMenuDialog(
    title: Text('Search in ${widget.appName}'),
    content: TextField(
      autofocus: true,
      maxLength: 200,
      textInputAction: TextInputAction.search,
      decoration: const InputDecoration(
        labelText: 'Search for',
        counterText: '',
      ),
      onChanged: (value) => setState(() => query = value),
      onSubmitted: submit,
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: query.trim().isEmpty ? null : () => submit(query),
        child: const Text('Search'),
      ),
    ],
  );
}
