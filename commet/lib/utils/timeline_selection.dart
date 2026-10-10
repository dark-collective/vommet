import 'package:flutter/foundation.dart';

/// Plain text currently selected in a room timeline (desktop), or null.
///
/// The timeline's SelectionArea suppresses Flutter's own selection toolbar
/// because right-click already opens the message menu; the message menu reads
/// this to offer "Copy selection".
class TimelineSelection {
  static final ValueNotifier<String?> current = ValueNotifier(null);

  static void update(String? text) {
    current.value = (text == null || text.isEmpty) ? null : text;
  }
}
