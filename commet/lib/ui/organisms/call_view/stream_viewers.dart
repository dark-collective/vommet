import 'package:commet/client/components/voip/voip_session.dart';
import 'package:commet/client/components/voip/voip_stream.dart';
import 'package:commet/client/components/voip/voip_stream_watching.dart';
import 'package:commet/ui/atoms/redaction_scope.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Vommet: who watches a screen share, as on Discord: an eye with the count
/// and their pictures on a watched stream's top bar, "3 watching" on your
/// own stream's tile; pointing at it lists them ("Watching — 3"). Nothing
/// while nobody does.
class StreamViewers extends StatelessWidget {
  const StreamViewers(
      {required this.session,
      required this.stream,
      this.ownStream = false,
      super.key});

  final VoipSession session;
  final VoipStream stream;

  /// On your own stream's tile: "3 watching" rather than an eye.
  final bool ownStream;

  static String streamViewersCount(int count) => Intl.message("$count watching",
      name: "streamViewersCount",
      args: [count],
      desc:
          "On your own screen share's tile in a call: how many people watch it");

  static String streamViewersTitle(int count) => Intl.message(
      "Watching — $count",
      name: "streamViewersTitle",
      args: [count],
      desc:
          "Heading of the list of who watches a screen share, shown when pointing at its viewer count");

  static String get streamViewersYou => Intl.message("(you)",
      name: "streamViewersYou",
      desc: "After your own name in the list of who watches a screen share");

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: session.onStateChanged,
      builder: (context, _) {
        final viewers =
            VoipStreamWatching.of(session)?.viewersOf(stream) ?? const [];
        if (viewers.isEmpty) return const SizedBox.shrink();
        return Tooltip(
          richMessage: _list(context, viewers),
          padding: const EdgeInsets.fromLTRB(12, 10, 16, 10),
          decoration: BoxDecoration(
              color: const Color(0xf0111214),
              borderRadius: BorderRadius.circular(8)),
          child: ownStream ? _own(context, viewers) : _chip(context, viewers),
        );
      },
    );
  }

  Widget _avatars(BuildContext context, List<String> viewers, double radius) {
    final room = session.client.getRoom(session.roomId);
    final shown = viewers.take(3).toList();
    final step = radius * 1.3;
    return SizedBox(
      width: radius * 2 + step * (shown.length - 1),
      height: radius * 2,
      child: Stack(children: [
        for (var i = 0; i < shown.length; i++)
          Positioned(
            left: step * i,
            child: Builder(builder: (context) {
              final m = room?.getMemberOrFallback(shown[i]);
              return Container(
                decoration: const BoxDecoration(
                    shape: BoxShape.circle, color: Colors.black),
                padding: const EdgeInsets.all(1),
                child: tiamat.Avatar(
                    radius: radius - 1,
                    image: m?.avatar,
                    placeholderColor: m?.defaultColor,
                    placeholderText: m?.displayName ?? shown[i],
                    redactionKey: shown[i]),
              );
            }),
          ),
      ]),
    );
  }

  Widget _chip(BuildContext context, List<String> viewers) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: .6),
            borderRadius: BorderRadius.circular(6)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.visibility_rounded, size: 14, color: Colors.white),
          const SizedBox(width: 4),
          Text("${viewers.length}",
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.white)),
          const SizedBox(width: 5),
          _avatars(context, viewers, 8),
        ]),
      );

  Widget _own(BuildContext context, List<String> viewers) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        _avatars(context, viewers, 9),
        const SizedBox(width: 6),
        Text(streamViewersCount(viewers.length),
            style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: Colors.white)),
      ]);

  InlineSpan _list(BuildContext context, List<String> viewers) {
    final room = session.client.getRoom(session.roomId);
    final self = session.client.self?.identifier;
    final redaction = RedactionScope.of(context);
    return TextSpan(
      style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.6),
      children: [
        TextSpan(
            text: streamViewersTitle(viewers.length),
            style: const TextStyle(fontWeight: FontWeight.w700)),
        for (final id in viewers) ...[
          const TextSpan(text: "\n"),
          TextSpan(
              text: redaction.name(
                  room?.getMemberOrFallback(id).displayName ?? id, id)),
          if (id == self)
            TextSpan(
                text: " $streamViewersYou",
                style: const TextStyle(color: Colors.white60, fontSize: 12)),
        ],
      ],
    );
  }
}
