import 'package:commet/ui/atoms/voice_participant_row.dart';
import 'package:commet/ui/organisms/call_view/stream_watch_card.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Vommet: the tile of someone sharing their screen (stream watching), as on
/// Discord. It carries LIVE; pointing at it dims it and shows "Watch stream"
/// ("Show stream" once you watch), and a click anywhere on it opens their
/// stream big ([onOpen]). Without a mouse, a tap does the same and the
/// corner chip says what it will do.
class LivePersonTile extends StatefulWidget {
  const LivePersonTile(
      {required this.child,
      required this.watched,
      required this.onOpen,
      super.key});

  static String get liveTileShowButton => Intl.message("Show stream",
      name: "liveTileShowButton",
      desc:
          "Call view, tile of someone sharing their screen that you already watch: button that shows their stream big");

  static String get liveTileWatchingTag => Intl.message("watching",
      name: "liveTileWatchingTag",
      desc:
          "Call view, tile of someone sharing their screen: small tag saying you watch their stream");

  final Widget child;

  /// Whether you already watch their stream.
  final bool watched;

  final VoidCallback onOpen;

  @override
  State<LivePersonTile> createState() => _LivePersonTileState();
}

class _LivePersonTileState extends State<LivePersonTile> {
  bool hovering = false;

  @override
  Widget build(BuildContext context) {
    final watched = widget.watched;
    return Semantics(
      button: true,
      label: watched
          ? VoiceParticipantRow.voiceRowShowTooltip
          : VoiceParticipantRow.voiceRowWatchTooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => hovering = true),
        onExit: (_) => setState(() => hovering = false),
        child: GestureDetector(
          // Wins over the call view's own tap (which would show this
          // person's picture big instead of their stream).
          behavior: HitTestBehavior.opaque,
          onTap: widget.onOpen,
          child: Stack(fit: StackFit.passthrough, children: [
            widget.child,
            if (hovering)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: .45),
                      borderRadius: BorderRadius.circular(8)),
                  child: Center(
                    child: StreamWatchButton(widget.onOpen,
                        label:
                            watched ? LivePersonTile.liveTileShowButton : null,
                        icon: watched
                            ? Icons.open_in_full_rounded
                            : Icons.play_arrow_rounded),
                  ),
                ),
              ),
            const Positioned(left: 8, top: 8, child: StreamLivePill()),
            if (!hovering)
              Positioned(
                right: 8,
                top: watched ? null : 8,
                bottom: watched ? 8 : null,
                child: StreamOverlayTag(
                    watched
                        ? LivePersonTile.liveTileWatchingTag
                        : StreamWatchCard.streamWatchShort,
                    leading:
                        watched ? Icons.visibility : Icons.play_arrow_rounded),
              ),
          ]),
        ),
      ),
    );
  }
}
