import 'package:commet/ui/organisms/call_view/stream_watch_card.dart';
import 'package:flutter/material.dart';

/// Vommet: the tile of someone sharing their screen (stream watching), as on
/// Discord: it only carries LIVE. Their stream has its own tile right after
/// it ([StreamTile]), which is where you watch it; a click on this one shows
/// the person big, like any other tile.
class LivePersonTile extends StatelessWidget {
  const LivePersonTile({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(fit: StackFit.passthrough, children: [
      child,
      const Positioned(left: 8, top: 8, child: StreamLivePill()),
    ]);
  }
}
