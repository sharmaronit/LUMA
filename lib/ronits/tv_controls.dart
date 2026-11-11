import 'package:flutter/material.dart';
import '../luma_channel.dart';
import 'focus_feedback.dart';
import 'menu_dialog.dart';
import 'motion.dart';

@immutable
class TvInput {
  const TvInput({required this.id, required this.label});
  final String id, label;
}

/// Sleep timer and input switching; the platform channel in the app, a fake
/// in tests.
abstract class TvControls {
  Future<List<TvInput>> inputs();
  Future<bool> switchInput(String id);
  Future<DateTime?> sleepEnd();
  Future<DateTime?> setSleep(int minutes);
  Future<bool> canTurnOff();
  Future<bool> requestTurnOff();
}

class ChannelTvControls implements TvControls {
  ChannelTvControls([LumaChannel? channel])
    : _channel = channel ?? LumaChannel();
  final LumaChannel _channel;
  @override
  Future<List<TvInput>> inputs() async => [
    for (final item in await _channel.getTvInputs())
      TvInput(id: item['id'] as String, label: item['label'] as String? ?? ''),
  ];
  @override
  Future<bool> switchInput(String id) => _channel.switchTvInput(id);
  @override
  Future<DateTime?> sleepEnd() => _channel.getSleepTimer();
  @override
  Future<DateTime?> setSleep(int minutes) => _channel.setSleepTimer(minutes);
  @override
  Future<bool> canTurnOff() => _channel.canTurnOffTv();
  @override
  Future<bool> requestTurnOff() => _channel.requestTurnOffPermission();
}

const sleepTimerChoices = [0, 15, 30, 60, 90];

String sleepChoiceLabel(int minutes) {
  if (minutes == 0) return 'Off';
  if (minutes < 60) return '$minutes minutes';
  final hours = minutes ~/ 60, rest = minutes % 60;
  return '$hours hour${hours == 1 ? '' : 's'}${rest == 0 ? '' : ' $rest min'}';
}

String sleepLabel(DateTime? end, [DateTime? now]) {
  if (end == null) return 'Off';
  final left = end.difference(now ?? DateTime.now());
  if (left.inSeconds <= 0) return 'Off';
  final minutes = (left.inSeconds / 60).ceil();
  return minutes >= 60
      ? '${minutes ~/ 60} h ${minutes % 60} min left'
      : '$minutes min left';
}

/// Picker for the sleep timer. Returns the new end time (null = off), or
/// throws nothing and returns the previous value when dismissed.
Future<DateTime?> showSleepTimerPicker(
  BuildContext context,
  TvControls controls,
  DateTime? current,
) async {
  var end = current;
  var allowed = await controls.canTurnOff();
  if (!context.mounted) return end;
  await showLumaDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => StatefulBuilder(
      builder: (_, update) => LumaMenuDialog(
        title: const Text('Sleep timer'),
        content: FocusHighlightLayer(
          menu: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!allowed)
                TvMenuRow(
                  key: const ValueKey('sleep-allow-turn-off'),
                  // Something must hold focus or the remote does nothing.
                  autofocus: true,
                  icon: Icons.power_settings_new_rounded,
                  title: 'Allow Luma to turn the TV off',
                  subtitle: 'One-time Android permission for the sleep timer',
                  onPressed: () async {
                    await controls.requestTurnOff();
                    final now = await controls.canTurnOff();
                    if (dialogContext.mounted) update(() => allowed = now);
                  },
                ),
              for (final minutes in sleepTimerChoices)
                TvMenuRow(
                  key: ValueKey('sleep-$minutes'),
                  autofocus: allowed && minutes == 0,
                  title: sleepChoiceLabel(minutes),
                  selected: minutes == 0 && end == null,
                  onPressed: () async {
                    end = await controls.setSleep(minutes);
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
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
  return end;
}

Future<void> showInputPicker(
  BuildContext context,
  TvControls controls,
  List<TvInput> inputs,
) => showLumaDialog<void>(
  context: context,
  builder: (dialogContext) => LumaMenuDialog(
    title: const Text('Input'),
    content: FocusHighlightLayer(
      menu: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final input in inputs)
            TvMenuRow(
              key: ValueKey('tv-input-${input.id}'),
              autofocus: input == inputs.first,
              icon: Icons.settings_input_hdmi_rounded,
              title: input.label,
              onPressed: () async {
                Navigator.pop(dialogContext);
                await controls.switchInput(input.id);
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
);
