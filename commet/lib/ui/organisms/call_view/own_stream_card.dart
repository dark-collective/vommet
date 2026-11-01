import 'dart:ui' as ui;

import 'package:commet/client/components/voip/share_quality.dart';
import 'package:commet/client/components/voip/voip_session.dart';
import 'package:commet/client/components/voip/voip_stream.dart';
import 'package:commet/ui/organisms/call_view/share_quality_picker.dart';
import 'package:commet/ui/organisms/call_view/stream_viewers.dart';
import 'package:commet/ui/organisms/call_view/stream_watch_card.dart';
import 'package:flutter/material.dart';

/// Vommet: your own screen share as its own tile next to yours, as on
/// Discord (stream watching): a dimmed preview, so the call doesn't show a
/// mirror of your screen, with "You're live" and Stop streaming. Tapping the
/// tile (outside the button) makes it the big one, like any other tile.
class OwnStreamCard extends StatelessWidget {
  const OwnStreamCard(
      {required this.stream, required this.onStop, this.session, super.key});

  final VoipStream stream;
  final Future<void> Function()? onStop;

  /// Vommet: the call, for the stream settings gear (quality while live).
  final VoipSession? session;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
          color: const Color(0xff15171a),
          borderRadius: BorderRadius.circular(8)),
      child: LayoutBuilder(builder: (context, box) {
        final compact = box.maxHeight < 170 || box.maxWidth < 220;
        return Stack(fit: StackFit.expand, children: [
          ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 1.5, sigmaY: 1.5),
              child: IgnorePointer(
                  child: stream.buildVideoRenderer(BoxFit.cover,
                      ValueKey("ownStreamPreview_${stream.streamId}")))),
          Container(color: Colors.black.withValues(alpha: .55)),
          Center(child: compact ? _compact() : _full(session)),
          if (!compact) ...[
            const Positioned(left: 8, top: 8, child: StreamLivePill()),
            const Positioned(
                left: 8,
                bottom: 8,
                child: StreamOverlayTag("Your stream",
                    leading: Icons.screen_share)),
            if (session is ShareQualityTarget)
              Positioned(
                  right: 8,
                  top: 8,
                  child: StreamSettingsButton(session: session!)),
          ],
        ]);
      }),
    );
  }

  Widget _full(VoipSession? session) =>
      Column(mainAxisSize: MainAxisSize.min, children: [
        const Text("You're live",
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Colors.white)),
        const SizedBox(height: 4),
        const Text("Sharing your screen",
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Colors.white70)),
        // Vommet: who's watching.
        if (session != null) ...[
          const SizedBox(height: 8),
          StreamViewers(session: session, stream: stream, ownStream: true),
        ],
        if (onStop != null) ...[
          const SizedBox(height: 12),
          _StopButton(onStop!),
        ],
      ]);

  Widget _compact() => Column(mainAxisSize: MainAxisSize.min, children: [
        const StreamLivePill(size: 9),
        const SizedBox(height: 6),
        if (onStop != null)
          _StopButton(onStop!, compact: true)
        else
          const Text("Your stream",
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.white)),
      ]);
}

class _StopButton extends StatelessWidget {
  const _StopButton(this.onStop, {this.compact = false});
  final Future<void> Function() onStop;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: streamLiveRed,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        mouseCursor: WidgetStateMouseCursor.clickable,
        borderRadius: BorderRadius.circular(8),
        onTap: onStop,
        child: Padding(
          padding: EdgeInsets.symmetric(
              horizontal: compact ? 8 : 12, vertical: compact ? 5 : 7),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.stop_screen_share_outlined,
                size: compact ? 14 : 16, color: Colors.white),
            const SizedBox(width: 6),
            Text(compact ? "Stop" : "Stop streaming",
                style: TextStyle(
                    fontSize: compact ? 12 : 12.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.white)),
          ]),
        ),
      ),
    );
  }
}
