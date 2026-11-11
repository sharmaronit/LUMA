import 'dart:async';
import 'dart:convert';
import 'package:flutter/scheduler.dart';

/// Opt-in, temporary on-device measurement for release APKs without a VM service.
/// No callback remains after the 30-second sample; normal builds do not enable it.
void startFrameProbe() {
  if (!const bool.fromEnvironment('LUMA_FRAME_PROBE')) return;
  final frames = <FrameTiming>[];
  void record(List<FrameTiming> timings) => frames.addAll(timings);
  Timer(const Duration(seconds: 5), () {
    SchedulerBinding.instance.addTimingsCallback(record);
    print('LUMA_FRAME_PROBE_READY');
    Timer(const Duration(seconds: 30), () {
      SchedulerBinding.instance.removeTimingsCallback(record);
      Map<String, Object> stats(List<double> values) {
        values.sort();
        if (values.isEmpty) return {'count': 0};
        double q(double p) =>
            values[(values.length * p).floor().clamp(0, values.length - 1)];
        return {
          'count': values.length,
          'p50': q(.5),
          'p90': q(.9),
          'p99': q(.99),
          'max': values.last,
          'overBudget': values.where((v) => v > 1000 / 59.94006).length,
        };
      }

      print(
        'LUMA_FRAME_TIMINGS ${jsonEncode({'build': stats(frames.map((f) => f.buildDuration.inMicroseconds / 1000).toList()), 'raster': stats(frames.map((f) => f.rasterDuration.inMicroseconds / 1000).toList()), 'vsyncOverhead': stats(frames.map((f) => f.vsyncOverhead.inMicroseconds / 1000).toList())})}',
      );
    });
  });
}
