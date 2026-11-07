// Vommet issue 982: compact passive rows, using only recent loaded events.
import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/client/matrix/timeline_events/matrix_timeline_event_zooid.dart';
import 'package:commet/ui/atoms/redaction_scope.dart';
import 'package:commet/ui/molecules/timeline_events/timeline_event_layout.dart';
import 'package:flutter/material.dart';

class TimelineEventViewZooid extends StatefulWidget {
  const TimelineEventViewZooid(
      {super.key, required this.event, required this.room, this.timeline});
  final MatrixTimelineEventZooid event;
  final Room room;
  final Timeline? timeline;

  @override
  State<TimelineEventViewZooid> createState() => _ZooidState();
}

class _ZooidState extends State<TimelineEventViewZooid>
    implements TimelineEventViewWidget {
  final List<StreamSubscription<int>> _subs = [];
  Set<String> _ids = {};
  late MatrixTimelineEventZooid _event;
  String? _body;
  bool _queued = false;

  @override
  void initState() {
    super.initState();
    _event = widget.event;
    _read();
    _attach();
  }

  void _attach() {
    final timeline = widget.timeline;
    if (timeline != null) {
      for (final stream in [
        timeline.onChange.stream,
        timeline.onEventAdded.stream,
        timeline.onRemove.stream
      ]) {
        _subs.add(stream.listen((i) {
          if (i < 0 || i >= timeline.events.length) return;
          final changed = timeline.events[i];
          if (!_ids.contains(changed.eventId) &&
              !(changed is MatrixTimelineEventZooid &&
                  changed.toolKey == _event.toolKey)) return;
          // Removal is announced before mutation; read the settled list.
          if (_queued) return;
          _queued = true;
          scheduleMicrotask(() {
            _queued = false;
            if (!mounted) return;
            final before = _body;
            _read();
            if (before != _body) setState(() {});
          });
        }));
      }
    }
  }

  void _read() {
    final timeline = widget.timeline;
    if (_event.event.redacted) {
      _body = null;
      return;
    }
    if (_event.isEnd) {
      _body = MatrixTimelineEventZooid.finished;
      if (_event.event.content['produced_output'] == false) {
        _body = '$_body\n${MatrixTimelineEventZooid.noText}';
      }
      return;
    }
    // Bounded per changed tool, with no network or account/history scan.
    // Older/orphan updates remain honestly incomplete beyond this window.
    final candidates = <String, MatrixTimelineEventZooid>{};
    for (final e in (timeline?.events ?? [_event]).take(200)) {
      if (e is MatrixTimelineEventZooid &&
          !e.event.redacted &&
          !e.isEnd &&
          e.toolKey == _event.toolKey) {
        candidates.putIfAbsent(e.eventId, () => e);
      }
    }
    if (timeline == null) candidates[_event.eventId] = _event;
    if (timeline != null &&
        timeline.events.length > 200 &&
        !candidates.containsKey(_event.eventId)) {
      // An older visible row keeps only its own received evidence.
      _ids = {_event.eventId};
      _body = '${_event.plainTextBody}\n'
          '${MatrixTimelineEventZooid.statusLabel(null)}';
      return;
    }
    final events = candidates.values.toList(); // SDK order: newest first.
    _ids = candidates.keys.toSet();
    final parent = events
        .where((e) => e.event.type == MatrixTimelineEventZooid.tool)
        .lastOrNull;
    final owner = parent ?? events.firstOrNull;
    if (owner?.eventId != _event.eventId) {
      _body = null;
      return;
    }
    Object? status;
    for (final e in events.reversed) {
      if (e.event.content.containsKey('status'))
        status = e.event.content['status'];
    }
    _body = '${parent?.plainTextBody ?? MatrixTimelineEventZooid.unavailable}\n'
        '${MatrixTimelineEventZooid.statusLabel(status)}';
  }

  @override
  void didUpdateWidget(covariant TimelineEventViewZooid oldWidget) {
    super.didUpdateWidget(oldWidget);
    final changedTimeline = oldWidget.timeline != widget.timeline;
    if (changedTimeline) {
      for (final sub in _subs) {
        sub.cancel();
      }
      _subs.clear();
      _attach();
    }
    if (changedTimeline || !identical(oldWidget.event, widget.event)) {
      _event = widget.event;
      _read();
    }
  }

  @override
  void update(int newIndex) {
    final event = widget.timeline?.events[newIndex];
    if (event is! MatrixTimelineEventZooid || identical(event, _event)) return;
    _event = event;
    setState(_read);
  }

  @override
  void dispose() {
    for (final sub in _subs) {
      sub.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final body = _body;
    if (body == null) return const SizedBox.shrink();
    final redaction = RedactionScope.of(context);
    final name = widget.room.getMemberOrFallback(_event.senderId).displayName;
    final theme = Theme.of(context);
    return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(redaction.name(name, _event.senderId),
              style: theme.textTheme.labelMedium),
          RedactedText(body, style: theme.textTheme.bodyMedium),
          Text(MatrixTimelineEventZooid.received,
              style: theme.textTheme.labelSmall),
        ]));
  }
}
