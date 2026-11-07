// Vommet issue 982: received activity claims only; no interactive actions.
import 'package:commet/client/matrix/timeline_events/matrix_timeline_event.dart';
import 'package:intl/intl.dart';
import 'package:matrix/matrix.dart' as matrix;

class MatrixTimelineEventZooid extends MatrixTimelineEvent {
  MatrixTimelineEventZooid(super.event, {required super.client});

  static const tool = 'dev.zooid.tool_call';
  static const update = 'dev.zooid.tool_call_update';
  static const end = 'dev.zooid.turn.end';

  static bool supports(matrix.Event event) {
    if (!const [tool, update, end].contains(event.type)) return false;
    final c = event.content;
    final rel = c['m.relates_to'];
    if (rel is! Map ||
        rel['rel_type'] != 'm.thread' ||
        (rel['event_id'] is! String || (rel['event_id'] as String).isEmpty) ||
        (c['session_id'] is! String || (c['session_id'] as String).isEmpty))
      return false;
    return event.type == end ||
        ((event.type == tool || event.type == update) &&
            c['tool_call_id'] is String &&
            (c['tool_call_id'] as String).isNotEmpty &&
            (event.type == update || c['title'] is String));
  }

  // A timeline already belongs to one account/room. Include both as well
  // as the real sender, root and session when projecting supplied events.
  Object get toolKey => (
        client.identifier,
        event.room.id,
        senderId,
        (event.content['m.relates_to'] as Map?)?['event_id'],
        event.content['session_id'],
        event.content['tool_call_id']
      );

  bool get isEnd => event.type == end;

  @override
  String get plainTextBody => isEnd
      ? finished
      : event.type == tool
          ? (event.content['title'] as String? ?? unavailable)
          : unavailable;

  static String get finished => Intl.message('Finished (turn ended)',
      name: 'zooidTurnFinished', desc: 'A turn ended, not a claim of success');
  static String get noText => Intl.message('No text reply reported',
      name: 'zooidNoText',
      desc: 'Turn end explicitly reported no flushed text');
  static String get unavailable =>
      Intl.message('Tool activity · details unavailable',
          name: 'zooidToolUnavailable',
          desc: 'A tool update has no loaded parent');
  static String get received => Intl.message('Last received activity',
      name: 'zooidReceivedActivity',
      desc: 'Activity is reported, not a live guarantee');
  static String statusLabel(Object? status) => switch (status) {
        'pending' => Intl.message('Pending', name: 'zooidPending'),
        'in_progress' =>
          Intl.message('Working (reported)', name: 'zooidWorking'),
        'completed' =>
          Intl.message('Completed (reported)', name: 'zooidCompleted'),
        'failed' => Intl.message('Failed (reported)', name: 'zooidFailed'),
        _ => Intl.message('Status unavailable', name: 'zooidStatusUnavailable'),
      };
}
