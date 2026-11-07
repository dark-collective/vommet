// Vommet: Settings › Developer › Frame counter (Vommet issue 350). A live
// readout of RepaintStats: frames Flutter drew per minute, their build and
// raster times, and on Linux how often GTK redrew the window, per view.

import 'dart:async';

import 'package:commet/telemetry/repaint_stats.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class FrameCounterWidget extends StatefulWidget {
  const FrameCounterWidget({super.key});

  @override
  State<FrameCounterWidget> createState() => _FrameCounterWidgetState();
}

class _FrameCounterWidgetState extends State<FrameCounterWidget> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    RepaintStats.changed.addListener(_refresh);
    // The minute so far, while this page is open.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => _refresh());
  }

  @override
  void dispose() {
    _tick?.cancel();
    RepaintStats.changed.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  static String _time(DateTime t) =>
      "${t.hour.toString().padLeft(2, "0")}:${t.minute.toString().padLeft(2, "0")}";

  Widget _row(BuildContext context, List<String> cells, {bool header = false}) {
    final color = header
        ? Theme.of(context).colorScheme.onSurface
        : Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 2, 0, 2),
      child: Row(
        children: cells
            .map((c) => Expanded(child: tiamat.Text.labelLow(c, color: color)))
            .toList(),
      ),
    );
  }

  List<String> _cells(String when, RepaintMinute m) => [
        when,
        m.view.name,
        "${m.frames}",
        "${m.buildP95Ms} / ${m.rasterP95Ms}",
        m.nativeDraws?.toString() ?? "–",
        m.nativePaints?.toString() ?? "–",
      ];

  @override
  Widget build(BuildContext context) {
    final on = RepaintStats.running;
    final rows = RepaintStats.history.toList().reversed;
    return ExpansionTile(
        title: const tiamat.Text.labelEmphasised("Frame counter"),
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
        collapsedBackgroundColor:
            Theme.of(context).colorScheme.surfaceContainerLow,
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Flexible(
                      child: tiamat.Text.label(
                          "Count frames (keeps counting after you leave this page, until the app closes)"),
                    ),
                    tiamat.Switch(
                      state: RepaintStats.developerCounting,
                      onChanged: (value) => RepaintStats.setDeveloper(value),
                    ),
                  ],
                ),
                const tiamat.Text.labelLow(
                    "Frames: frames the app drew. Build / raster: 95th percentile ms. "
                    "Window draws / paints (Linux): how often the system redrew the window. "
                    "Many window draws with few frames means the window repaints without the app asking."),
                const SizedBox(height: 8),
                _row(
                    context,
                    [
                      "Minute",
                      "View",
                      "Frames",
                      "Build / raster",
                      "Window draws",
                      "Paints"
                    ],
                    header: true),
                if (on)
                  _row(context, _cells("now", RepaintStats.current()))
                else
                  const tiamat.Text.labelLow("Off."),
                ...rows.map((m) => _row(context, _cells(_time(m.end), m))),
              ],
            ),
          )
        ]);
  }
}
