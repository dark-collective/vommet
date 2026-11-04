import 'dart:math';

import 'package:commet/client/timeline_events/timeline_event.dart';
import 'package:commet/ui/molecules/timeline_events/timeline_view_entry.dart';

/// Vommet issue 354: how many events to ask the server for per page of older
/// history. In rooms where dozens of joins, leaves and name changes sit
/// between real messages, a whole page folds into one summary row, so the
/// view stays unfilled and asks again, one small page per round trip. Each
/// page that shows nothing doubles the next request (up to [max]); a page
/// that shows a message goes back to the normal size.
class HistoryPageSize {
  static const int normal = 30;
  static const int max = 240;

  int _current = normal;

  int get current => _current;

  /// Call after each page with the events it added.
  void notePage(Iterable<TimelineEvent> added) {
    noteShowedSomething(added.any(showsAsRow));
  }

  void noteShowedSomething(bool showedSomething) {
    _current = showedSomething ? normal : min(_current * 2, max);
  }

  /// Same rule as the timeline's "empty page" count: generic (state) and
  /// hidden events don't get a row of their own.
  static bool showsAsRow(TimelineEvent event) {
    final type = TimelineViewEntryState.eventToDisplayType(event);
    return type != TimelineEventWidgetDisplayType.generic &&
        type != TimelineEventWidgetDisplayType.hidden;
  }
}
