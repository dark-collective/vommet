import 'dart:async';
import 'dart:math';
import 'package:commet/client/components/voip/screen_share_status.dart';
import 'package:commet/client/components/voip/voip_session.dart';
import 'package:commet/client/components/voip/voip_stream.dart';
import 'package:commet/client/room.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/organisms/call_view/stream_watch_card.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// No media connection is made here. An already-joined call takes precedence
/// over state reports, including when it observes no screen-share tracks.
class ScreenShareReportsBuilder extends StatefulWidget {
  const ScreenShareReportsBuilder(
      {required this.room, required this.builder, super.key});
  final Room room;
  final Widget Function(BuildContext, Set<String>) builder;
  @override
  State<ScreenShareReportsBuilder> createState() =>
      _ScreenShareReportsBuilderState();
}

class _ScreenShareReportsBuilderState extends State<ScreenShareReportsBuilder> {
  final List<StreamSubscription> _subs = [];
  StreamSubscription? _callSub;
  Timer? _expiry;
  VoipSession? _call;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void didUpdateWidget(ScreenShareReportsBuilder old) {
    super.didUpdateWidget(old);
    if (old.room != widget.room) {
      _detach();
      _listen();
    }
  }

  void _listen() {
    _subs.add(ScreenShareStatus.experiment.onChanged.listen((_) {
      _detach();
      _listen();
      if (mounted) setState(() {});
    }));
    if (!ScreenShareStatus.experiment.value) return;
    final status = widget.room.getComponent<ScreenShareStatus>();
    if (status != null) {
      _subs.add(status.onScreenSharesChanged.listen((_) => _refresh()));
    }
    final sessions = clientManager?.callManager.currentSessions;
    if (sessions != null) {
      _subs.add(sessions.onListUpdated.listen((_) => _refresh()));
    }
    _attachCall();
  }

  void _attachCall() {
    VoipSession? next;
    for (final s
        in clientManager?.callManager.currentSessions ?? <VoipSession>[]) {
      if (s.roomId == widget.room.identifier &&
          s.client == widget.room.client &&
          s.state == VoipState.connected) {
        next = s;
        break;
      }
    }
    if (identical(next, _call)) return;
    _callSub?.cancel();
    _call = next;
    _callSub = next?.onStateChanged.listen((_) => _refresh());
  }

  void _refresh() {
    if (!mounted) return;
    _attachCall();
    setState(() {});
  }

  void _detach() {
    for (final sub in _subs) {
      sub.cancel();
    }
    _subs.clear();
    _callSub?.cancel();
    _call = null;
    _expiry?.cancel();
  }

  @override
  void dispose() {
    _detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _expiry?.cancel();
    if (!ScreenShareStatus.experiment.value) return widget.builder(context, {});
    final call = _call;
    if (call != null) {
      return widget.builder(context, {
        for (final s in call.streams)
          if (s.type == VoipStreamType.screenshare) s.streamUserId,
      });
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final reports =
        widget.room.getComponent<ScreenShareStatus>()?.screenShares ??
            const <String, int>{};
    final active = reports.entries.where((e) => e.value > now).toList();
    if (active.isNotEmpty) {
      final next = active.map((e) => e.value).reduce(min);
      // Cap long waits so unusual remote timestamps cannot overflow timers.
      _expiry =
          Timer(Duration(milliseconds: min(next - now, 3600000)), _refresh);
    }
    return widget.builder(context, {for (final e in active) e.key});
  }
}

/// A passive discovery label. Joining/watching stays a separate explicit action.
class ScreenShareStatusBadge extends StatelessWidget {
  const ScreenShareStatusBadge({this.name, this.count, super.key});
  final String? name;
  final int? count;
  static String get explanation => Intl.message(
      "Screen-share status is reported by participants' clients. It may be out of date; shares from other clients may not appear.",
      name: 'screenShareStatusExplanation',
      desc: 'Prejoin screen-share status limitation');
  static String reportedBy(String name) =>
      Intl.message("$name: screen sharing reported",
          args: [name],
          name: 'screenShareStatusReportedBy',
          desc: 'Accessible name of a passive screen-share badge');
  static String reportedCount(int count) => Intl.plural(count,
      one: '1 person reports screen sharing',
      other: '$count people report screen sharing',
      args: [count],
      name: 'screenShareStatusReportedCount',
      desc: 'Accessible label of a room screen-share count');
  @override
  Widget build(BuildContext context) {
    final label =
        count != null ? reportedCount(count!) : reportedBy(name ?? '');
    return Semantics(
        label: label,
        child: Tooltip(
            message: '$label. $explanation',
            child: ExcludeSemantics(
                child: Row(mainAxisSize: MainAxisSize.min, children: [
              const StreamLivePill(size: 10),
              if (count != null) ...[
                const SizedBox(width: 3),
                Text('$count',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontSize: 12,
                        fontWeight: FontWeight.w600))
              ],
            ]))));
  }
}

class RoomScreenShareCount extends StatelessWidget {
  const RoomScreenShareCount(this.room, {super.key});
  final Room room;
  @override
  Widget build(BuildContext context) => ScreenShareReportsBuilder(
      room: room,
      builder: (context, shares) => shares.isEmpty
          ? const SizedBox.shrink()
          : Padding(
              padding: const EdgeInsets.only(left: 6, right: 6),
              child: ScreenShareStatusBadge(count: shares.length)));
}
