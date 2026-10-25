import 'dart:ui' as ui;

import 'package:commet/client/components/voip/voip_session.dart';
import 'package:commet/client/components/voip/voip_stream.dart';
import 'package:commet/client/components/voip/voip_stream_watching.dart';
import 'package:commet/client/member.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;
import 'package:intl/intl.dart';

/// Vommet: the red used for LIVE marks, Discord's, in every theme.
const Color streamLiveRed = Color(0xffda373c);

/// Vommet: a small red LIVE label.
class StreamLivePill extends StatelessWidget {
  const StreamLivePill({this.size = 10, super.key});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: size * .45, vertical: 1),
      decoration: BoxDecoration(
          color: streamLiveRed, borderRadius: BorderRadius.circular(size * .4)),
      child: Text(StreamWatchCard.streamLiveBadge,
          style: TextStyle(
              fontSize: size,
              height: 1.25,
              letterSpacing: .6,
              fontWeight: FontWeight.w800,
              color: Colors.white)),
    );
  }
}

/// Vommet: a dark label over a stream (who's sharing, a mute mark).
class StreamOverlayTag extends StatelessWidget {
  const StreamOverlayTag(this.text, {this.leading, this.trailing, super.key});
  final String text;
  final IconData? leading;
  final IconData? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: .75),
          borderRadius: BorderRadius.circular(6)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (leading != null) ...[
          Icon(leading, size: 14, color: Colors.white),
          const SizedBox(width: 6),
        ],
        Flexible(
          child: Text(text,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.white)),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 6),
          Icon(trailing, size: 14, color: Colors.white),
        ],
      ]),
    );
  }
}

/// Vommet: someone's screen share you aren't watching (VoipStreamWatching).
/// Shows a softened live preview when the sharer sends a low-quality layer,
/// otherwise their picture on their colour. Tapping it starts watching.
class StreamWatchCard extends StatelessWidget {
  static String get streamLiveBadge => Intl.message("LIVE",
      name: "streamLiveBadge",
      desc:
          "Screen share card in a call: small red badge on a live screen share; keep very short");

  static String streamWatchSemanticLabel(String name) => Intl.message(
      "Watch $name's screen share",
      args: [name],
      name: "streamWatchSemanticLabel",
      desc:
          "Screen share card in a call: screen reader label; name is who is sharing");

  static String get streamWatchShort => Intl.message("Watch",
      name: "streamWatchShort",
      desc:
          "Screen share card in a call: short label on a small card; keep very short");

  static String streamIsSharing(String name) =>
      Intl.message("$name is sharing their screen",
          args: [name],
          name: "streamIsSharing",
          desc: "Screen share card in a call: name is who is sharing");

  static String get streamWatchButton => Intl.message("Watch stream",
      name: "streamWatchButton",
      desc:
          "Screen share card in a call: button that starts watching the screen share");

  const StreamWatchCard(
      {required this.stream,
      required this.session,
      required this.watching,
      required this.onWatch,
      super.key});

  final VoipStream stream;
  final VoipSession session;
  final VoipStreamWatching watching;
  final VoidCallback onWatch;

  @override
  Widget build(BuildContext context) {
    final room = session.client.getRoom(session.roomId);
    final member = room?.getMemberOrFallback(stream.streamUserId);
    final name = member?.displayName ?? stream.streamUserId;
    final color = member?.defaultColor ?? Colors.blueGrey;
    final preview = watching.hasPreview(stream)
        ? stream.buildVideoRenderer(
            BoxFit.cover, ValueKey("streamPreview_${stream.streamId}"))
        : null;

    return Semantics(
      button: true,
      label: StreamWatchCard.streamWatchSemanticLabel(name),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          mouseCursor: WidgetStateMouseCursor.clickable,
          borderRadius: BorderRadius.circular(8),
          onTap: onWatch,
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
                color: const Color(0xff15171a),
                borderRadius: BorderRadius.circular(8)),
            child: LayoutBuilder(builder: (context, box) {
              final compact = box.maxHeight < 170 || box.maxWidth < 220;
              return Stack(fit: StackFit.expand, children: [
                if (preview != null) ...[
                  ImageFiltered(
                      imageFilter:
                          ui.ImageFilter.blur(sigmaX: 1.2, sigmaY: 1.2),
                      child: IgnorePointer(child: preview)),
                  Container(color: Colors.black.withValues(alpha: .38)),
                ] else
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: const Alignment(0, -.2),
                        radius: 1.1,
                        colors: [
                          Color.lerp(color, Colors.black, .35)!,
                          Color.lerp(color, const Color(0xff15171a), .85)!,
                        ],
                      ),
                    ),
                  ),
                Center(
                    child: preview != null
                        ? (compact ? _compactLabel() : _WatchButton(onWatch))
                        : _sharer(member, name, color, compact)),
                if (preview != null && !compact) ...[
                  const Positioned(left: 8, top: 8, child: StreamLivePill()),
                  Positioned(
                      left: 8,
                      right: 8,
                      bottom: 8,
                      child: Align(
                          alignment: Alignment.centerLeft,
                          child: StreamOverlayTag(name,
                              leading: Icons.screen_share))),
                ],
              ]);
            }),
          ),
        ),
      ),
    );
  }

  Widget _compactLabel() => Column(mainAxisSize: MainAxisSize.min, children: [
        const StreamLivePill(size: 9),
        const SizedBox(height: 6),
        Text(streamWatchShort,
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.white)),
      ]);

  Widget _sharer(Member? member, String name, Color color, bool compact) {
    final radius = compact ? 18.0 : 30.0;
    final avatar = Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.bottomCenter,
      children: [
        Container(
          padding: EdgeInsets.all(compact ? 2 : 3),
          decoration:
              const BoxDecoration(color: streamLiveRed, shape: BoxShape.circle),
          child: tiamat.Avatar(
              radius: radius,
              image: member?.avatar,
              placeholderColor: color,
              placeholderText: name),
        ),
        Positioned(
            bottom: compact ? -6 : -7,
            child: StreamLivePill(size: compact ? 8 : 9)),
      ],
    );
    if (compact) {
      return Column(mainAxisSize: MainAxisSize.min, children: [
        avatar,
        const SizedBox(height: 10),
        Text(streamWatchShort,
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.white)),
      ]);
    }
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        avatar,
        const SizedBox(height: 14),
        Text(streamIsSharing(name),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.white)),
        const SizedBox(height: 10),
        _WatchButton(onWatch),
      ]),
    );
  }
}

class _WatchButton extends StatelessWidget {
  const _WatchButton(this.onPressed);
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xff1e1f22);
    return Material(
      color: Colors.white.withValues(alpha: .92),
      borderRadius: BorderRadius.circular(8),
      elevation: 3,
      child: InkWell(
        mouseCursor: WidgetStateMouseCursor.clickable,
        borderRadius: BorderRadius.circular(8),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.play_arrow_rounded, size: 18, color: ink),
            const SizedBox(width: 6),
            Text(StreamWatchCard.streamWatchButton,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600, color: ink)),
          ]),
        ),
      ),
    );
  }
}
