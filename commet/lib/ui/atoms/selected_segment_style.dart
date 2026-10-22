import 'package:flutter/material.dart';

/// Vommet issue 594: settings' segmented buttons hide the checkmark, so the
/// selected segment's default fill (`secondaryContainer`) was the only cue,
/// and on OLED/black themes it matches the background. This fills it with the
/// theme's accent colour instead; disabled and unselected segments keep the
/// defaults.
ButtonStyle selectedSegmentStyle(ColorScheme scheme) {
  bool accent(Set<WidgetState> states) =>
      states.contains(WidgetState.selected) &&
      !states.contains(WidgetState.disabled);
  return ButtonStyle(
    backgroundColor: WidgetStateProperty.resolveWith(
        (states) => accent(states) ? scheme.primary : null),
    foregroundColor: WidgetStateProperty.resolveWith(
        (states) => accent(states) ? scheme.onPrimary : null),
  );
}
