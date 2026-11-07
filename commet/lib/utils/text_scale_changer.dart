import 'dart:async';

import 'package:commet/main.dart';
import 'package:flutter/material.dart';

class TextScaleChanger extends StatefulWidget {
  const TextScaleChanger({required this.child, super.key});
  final Widget child;

  @override
  State<TextScaleChanger> createState() => _TextScaleChangerState();
}

class _TextScaleChangerState extends State<TextScaleChanger> {
  // Vommet issue 1195: stop observing this setting when the wrapper goes away.
  late final StreamSubscription<double> _subscription;

  @override
  void initState() {
    super.initState();
    _subscription =
        preferences.textScale.onChanged.listen((_) => setState(() {}));
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final multiplier = preferences.textScale.value;
    if (multiplier == 1.0) {
      return widget.child;
    }

    final media = MediaQuery.of(context);
    // Vommet issue 1195: multiply the platform's result, preserving its curve.
    return MediaQuery(
        data: media.copyWith(
            textScaler: _AppTextScaler(media.textScaler, multiplier)),
        child: widget.child);
  }
}

// Vommet issue 1195: App Text scale composes with OS accessibility scaling.
class _AppTextScaler extends TextScaler {
  const _AppTextScaler(this.platform, this.multiplier);

  final TextScaler platform;
  final double multiplier;

  @override
  double scale(double fontSize) => platform.scale(fontSize) * multiplier;

  // Compatibility estimate for consumers that have not migrated to scale().
  @override
  // ignore: deprecated_member_use
  double get textScaleFactor => platform.textScaleFactor * multiplier;

  @override
  bool operator ==(Object other) =>
      other is _AppTextScaler &&
      other.platform == platform &&
      other.multiplier == multiplier;

  @override
  int get hashCode => Object.hash(platform, multiplier);
}
