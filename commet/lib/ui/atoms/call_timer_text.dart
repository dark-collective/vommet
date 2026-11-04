import 'dart:async';

import 'package:commet/utils/call_duration.dart';
import 'package:flutter/material.dart';

/// Vommet: text with the time since [since], ticking every second.
/// [builder] turns the elapsed time ("41:05") into the text to show.
class CallTimerText extends StatefulWidget {
  const CallTimerText(
      {required this.since, this.builder, this.style, super.key});

  final DateTime since;
  final String Function(String elapsed)? builder;
  final TextStyle? style;

  @override
  State<CallTimerText> createState() => _CallTimerTextState();
}

class _CallTimerTextState extends State<CallTimerText> {
  Timer? ticker;

  @override
  void initState() {
    super.initState();
    ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final elapsed =
        CallDuration.format(DateTime.now().difference(widget.since));
    return Text(widget.builder?.call(elapsed) ?? elapsed,
        maxLines: 1, overflow: TextOverflow.ellipsis, style: widget.style);
  }
}
