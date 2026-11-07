// Vommet: the "Redacted" pill shown while redacted mode is on (Vommet issue
// 474). Tap turns redacted mode off; right-click or long-press opens
// Settings › Redacted mode. The pill itself is never redacted.

import 'package:commet/main.dart';
import 'package:commet/ui/atoms/redaction_scope.dart';
import 'package:commet/utils/redaction/redaction_preferences.dart';
import 'package:commet/utils/redaction/redaction_toggle.dart';
import 'package:flutter/material.dart';

class RedactedModePill extends StatelessWidget {
  const RedactedModePill({super.key, this.margin = EdgeInsets.zero});

  /// Space around the pill, only while it shows.
  final EdgeInsetsGeometry margin;

  static const Color amber = Color(0xFFE0A43A);
  static const Color onAmber = Color(0xFF1A1306);

  @override
  Widget build(BuildContext context) {
    // Rebuilds whenever the redaction settings change.
    RedactionScope.of(context);
    if (!preferences.redactionActive) return const SizedBox.shrink();

    return Padding(padding: margin, child: pill(context));
  }

  Widget pill(BuildContext context) {
    return Tooltip(
      message: redactedModeIndicatorTooltip,
      child: Material(
        color: amber,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => setRedactedMode(context, false),
          onLongPress: () => openRedactedModeSettings(context),
          onSecondaryTap: () => openRedactedModeSettings(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.visibility_off, size: 13, color: onAmber),
                const SizedBox(width: 4),
                Text(
                  redactedModeIndicator,
                  style: const TextStyle(
                      color: onAmber,
                      fontSize: 11,
                      fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
