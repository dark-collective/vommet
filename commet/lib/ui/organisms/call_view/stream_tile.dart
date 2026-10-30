import 'dart:ui' as ui;

import 'package:commet/client/components/voip/voip_session.dart';
import 'package:commet/client/components/voip/voip_stream.dart';
import 'package:commet/ui/organisms/call_view/stream_watch_card.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Vommet: what a stream tile shows ([StreamTile]).
enum StreamTileState {
  /// Not shown big: "Watch stream" and the small icon.
  idle,

  /// Already shown big in the call view: says so, nothing to press.
  shownBig,

  /// Playing in the mini-player: says so, with "Show here".
  inMiniPlayer,

  /// Playing in its own desktop window: says so, with "Dock back".
  inOwnWindow,
}

/// Vommet: what the small icon next to "Watch stream" does on a stream
/// tile. The call view picks one ([StreamTile.smallActionFor]).
enum StreamTileSmallAction {
  /// Another stream is big: watch this one beside it ([MultiStreamFocus]).
  sideBySide,

  /// Watch it in the floating mini-player ([StreamMiniPlayer]).
  miniPlayer,

  /// Desktop: watch it in its own OS window. Only offered once
  /// [StreamTile.popOutWindow] is set (Linux, StreamPopoutWindow.install);
  /// other desktops get [miniPlayer].
  popOutWindow,
}

/// Vommet: the own tile of a screen share in the call view's grid, as on
/// Discord, placed right after its sharer's tile (which only carries LIVE).
/// A thumbnail ([background]) with LIVE, the sharer's name ("Name · title"
/// when the title is known) and who's watching ([viewers]). Pointing at it
/// shows "Watch stream" ([onWatch], replaces the big stream) and a small
/// icon ([small], [onSmall]); without a mouse ([alwaysShowButtons]) both
/// stay shown and a long press offers the same in a sheet.
class StreamTile extends StatefulWidget {
  const StreamTile({
    required this.name,
    required this.background,
    required this.onWatch,
    required this.onSmall,
    this.title,
    this.avatar,
    this.mark,
    this.viewers,
    this.state = StreamTileState.idle,
    this.small = StreamTileSmallAction.miniPlayer,
    this.alwaysShowButtons = false,
    this.onShowHere,
    this.softenBackground = true,
    super.key,
  });

  static String get streamTileSideBySide => Intl.message("Watch side by side",
      name: "streamTileSideBySide",
      desc:
          "Call view, a screen share's tile while another stream is shown big: small button that watches this one next to it");

  static String get streamTileMiniPlayer => Intl.message("Watch in mini-player",
      name: "streamTileMiniPlayer",
      desc:
          "Call view, a screen share's tile: small button (and long-press menu item) that watches the stream in the small floating player");

  static String get streamTilePopOutWindow => Intl.message(
      "Pop out to its own window",
      name: "streamTilePopOutWindow",
      desc:
          "Call view, a screen share's tile on desktop: small button that opens the stream in a separate window");

  static String get streamTileInMiniPlayer => Intl.message(
      "Playing in the mini-player",
      name: "streamTileInMiniPlayer",
      desc:
          "Call view, a screen share's tile while that stream plays in the small floating player");

  static String get streamTileShowHere => Intl.message("Show here",
      name: "streamTileShowHere",
      desc:
          "Call view, a screen share's tile while it plays in the mini-player: button that brings it back into the call view, big");

  static String get streamTileInOwnWindow => Intl.message(
      "Playing in its own window",
      name: "streamTileInOwnWindow",
      desc:
          "Call view, a screen share's tile while that stream plays in a separate window");

  static String get streamTileDockBack => Intl.message("Dock back",
      name: "streamTileDockBack",
      desc:
          "Call view, a screen share's tile while it plays in a separate window: button that closes that window and brings the stream back into the call view, big");

  static String get streamTileShownBig => Intl.message("Watching",
      name: "streamTileShownBig",
      desc:
          "Call view, a screen share's tile while that stream is already shown big: says you watch it");

  /// The seam for watching a stream in its own desktop window: null until
  /// that window exists, so desktop offers the mini-player meanwhile. Set it
  /// to open the window; the small icon then offers it on desktop.
  static Future<void> Function(VoipSession session, VoipStream stream)?
      popOutWindow;

  static bool get popOutWindowAvailable => popOutWindow != null;

  /// The small icon's action: beside the big one when [othersBig] (another
  /// stream is big), the mini-player on phones ([phone]), otherwise its own
  /// window on desktop once [popOutWindow] is set.
  static StreamTileSmallAction smallActionFor(
      {required bool othersBig, required bool phone}) {
    if (othersBig) return StreamTileSmallAction.sideBySide;
    if (!phone && popOutWindowAvailable) {
      return StreamTileSmallAction.popOutWindow;
    }
    return StreamTileSmallAction.miniPlayer;
  }

  static IconData smallIcon(StreamTileSmallAction small) => switch (small) {
        StreamTileSmallAction.sideBySide => Icons.add_to_queue_rounded,
        StreamTileSmallAction.miniPlayer =>
          Icons.picture_in_picture_alt_outlined,
        StreamTileSmallAction.popOutWindow => Icons.open_in_new_rounded,
      };

  static String smallLabel(StreamTileSmallAction small) => switch (small) {
        StreamTileSmallAction.sideBySide => streamTileSideBySide,
        StreamTileSmallAction.miniPlayer => streamTileMiniPlayer,
        StreamTileSmallAction.popOutWindow => streamTilePopOutWindow,
      };

  /// The sharer's name, always shown.
  final String name;

  /// What they share (a window or app title), when known.
  final String? title;

  /// The sharer's picture in the name chip.
  final Widget? avatar;

  /// Vommet issue 853: the sharer's network mark, after the name.
  final Widget? mark;

  /// The thumbnail: the stream's preview, or a placeholder.
  final Widget background;

  /// Softens [background] (a stream preview) a little, as the Watch card
  /// does; off for a placeholder. In the mini-player it is always blurred.
  final bool softenBackground;

  /// Who's watching (an eye chip), if anyone.
  final Widget? viewers;

  final StreamTileState state;
  final StreamTileSmallAction small;

  /// No mouse (phones): the buttons are always shown.
  final bool alwaysShowButtons;

  final VoidCallback onWatch;
  final VoidCallback onSmall;

  /// In the mini-player or its own window: bring it back here.
  final VoidCallback? onShowHere;

  @override
  State<StreamTile> createState() => _StreamTileState();
}

class _StreamTileState extends State<StreamTile> {
  bool hovering = false;

  Future<void> _sheet() async {
    final small = widget.small == StreamTileSmallAction.sideBySide
        ? StreamTileSmallAction.sideBySide
        : StreamTileSmallAction.miniPlayer;
    final picked = await showModalBottomSheet<VoidCallback>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.play_arrow_rounded),
            title: Text(StreamWatchCard.streamWatchButton),
            onTap: () => Navigator.of(context).pop(widget.onWatch),
          ),
          ListTile(
            leading: Icon(StreamTile.smallIcon(small)),
            title: Text(StreamTile.smallLabel(small)),
            onTap: () => Navigator.of(context).pop(widget.onSmall),
          ),
        ]),
      ),
    );
    picked?.call();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final idle = state == StreamTileState.idle;
    final mini = state == StreamTileState.inMiniPlayer ||
        state == StreamTileState.inOwnWindow;
    final buttons = idle && (hovering || widget.alwaysShowButtons);
    final VoidCallback? onTap = switch (state) {
      StreamTileState.idle => widget.onWatch,
      StreamTileState.inMiniPlayer => widget.onShowHere,
      StreamTileState.inOwnWindow => widget.onShowHere,
      StreamTileState.shownBig => null,
    };

    return Semantics(
      button: onTap != null,
      label: StreamWatchCard.streamWatchSemanticLabel(widget.name),
      child: MouseRegion(
        cursor: onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
        onEnter: (_) => setState(() => hovering = true),
        onExit: (_) => setState(() => hovering = false),
        child: GestureDetector(
          // Wins over the call view's own tap on the tile.
          behavior: HitTestBehavior.opaque,
          onTap: onTap ?? () {},
          onLongPress: idle ? _sheet : null,
          child: Container(
            clipBehavior: Clip.antiAlias,
            foregroundDecoration: hovering && onTap != null
                ? BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white, width: 2))
                : null,
            decoration: BoxDecoration(
                color: const Color(0xff15171a),
                borderRadius: BorderRadius.circular(8)),
            child: LayoutBuilder(builder: (context, box) {
              final compact = box.maxHeight < 150 || box.maxWidth < 240;
              final blur = mini ? 6.0 : (widget.softenBackground ? 1.2 : 0.0);
              final background = IgnorePointer(child: widget.background);
              return Stack(fit: StackFit.expand, children: [
                if (blur > 0)
                  ImageFiltered(
                      imageFilter:
                          ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
                      child: background)
                else
                  background,
                Container(
                    color: Colors.black.withValues(
                        alpha: mini ? .6 : (buttons && hovering ? .28 : .42))),
                Center(child: _middle(compact, buttons)),
                const Positioned(left: 8, top: 8, child: StreamLivePill()),
                Positioned(
                  left: 8,
                  right: 8,
                  bottom: 8,
                  child: Row(children: [
                    Expanded(
                        child: Align(
                            alignment: Alignment.centerLeft,
                            child: _nameChip(compact))),
                    if (widget.viewers != null) ...[
                      const SizedBox(width: 6),
                      widget.viewers!,
                    ],
                  ]),
                ),
              ]);
            }),
          ),
        ),
      ),
    );
  }

  Widget _middle(bool compact, bool buttons) {
    switch (widget.state) {
      case StreamTileState.shownBig:
        return _status(Icons.visibility, StreamTile.streamTileShownBig, null);
      case StreamTileState.inMiniPlayer:
        return _status(Icons.picture_in_picture_alt_outlined,
            StreamTile.streamTileInMiniPlayer, widget.onShowHere);
      case StreamTileState.inOwnWindow:
        return _status(Icons.open_in_new_rounded,
            StreamTile.streamTileInOwnWindow, widget.onShowHere,
            actionLabel: StreamTile.streamTileDockBack,
            actionIcon: Icons.login_rounded);
      case StreamTileState.idle:
        if (!buttons) return const SizedBox.shrink();
        final box = compact ? 32.0 : 38.0;
        return Row(mainAxisSize: MainAxisSize.min, children: [
          Flexible(
            child: StreamWatchButton(widget.onWatch,
                label: compact ? StreamWatchCard.streamWatchShort : null),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: StreamTile.smallLabel(widget.small),
            child: Material(
              color: Colors.black.withValues(alpha: .62),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: const BorderSide(color: Colors.white24)),
              child: InkWell(
                key: const ValueKey("streamTileSmall"),
                mouseCursor: WidgetStateMouseCursor.clickable,
                borderRadius: BorderRadius.circular(8),
                onTap: widget.onSmall,
                child: SizedBox(
                  width: box,
                  height: box,
                  child: Icon(StreamTile.smallIcon(widget.small),
                      size: box * .5, color: Colors.white),
                ),
              ),
            ),
          ),
        ]);
    }
  }

  Widget _status(IconData icon, String text, VoidCallback? action,
      {String? actionLabel, IconData? actionIcon}) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 26, color: Colors.white70),
        const SizedBox(height: 6),
        Text(text,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.white70)),
        if (action != null) ...[
          const SizedBox(height: 8),
          StreamWatchButton(action,
              key: const ValueKey("streamTileShowHere"),
              label: actionLabel ?? StreamTile.streamTileShowHere,
              icon: actionIcon ?? Icons.open_in_full_rounded),
        ],
      ]),
    );
  }

  Widget _nameChip(bool compact) {
    final title = compact ? null : widget.title;
    return Container(
      padding: EdgeInsets.fromLTRB(widget.avatar == null ? 8 : 4, 3, 8, 3),
      decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: .72),
          borderRadius: BorderRadius.circular(6)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (widget.avatar != null) ...[
          widget.avatar!,
          const SizedBox(width: 6),
        ],
        Flexible(
          child: Text.rich(
            TextSpan(children: [
              TextSpan(
                  text: widget.name,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              if (title != null && title.isNotEmpty)
                TextSpan(
                    text: " · $title",
                    style: const TextStyle(
                        fontWeight: FontWeight.w500, color: Colors.white70)),
            ]),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12.5, color: Colors.white),
          ),
        ),
        if (widget.mark != null) widget.mark!,
      ]),
    );
  }
}

/// Vommet: a stream tile's thumbnail while there is no preview: the
/// sharer's picture on their color.
class StreamTilePlaceholder extends StatelessWidget {
  const StreamTilePlaceholder(
      {required this.color, required this.avatar, super.key});

  final Color color;
  final Widget avatar;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
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
      child: Center(child: avatar),
    );
  }
}
