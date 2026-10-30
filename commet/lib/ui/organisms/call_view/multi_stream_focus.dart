import 'package:commet/client/components/voip/voip_session.dart';
import 'package:commet/client/components/voip/voip_stream.dart';
import 'package:commet/client/components/voip/voip_stream_watching.dart';
import 'package:commet/ui/organisms/call_view/stream_watch_card.dart';
import 'package:commet/ui/organisms/call_view/voip_stream_view.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Vommet: the screen shares you watch that the call view shows big next to
/// its main stream, as on Discord. Two side by side, up to four in a 2x2;
/// "Show big" pins one big with the others live in a column beside it (a
/// strip under it on narrow windows and phones).
class MultiStreamFocus {
  static String get multiStreamShowBig => Intl.message("Show big",
      name: "multiStreamShowBig",
      desc:
          "Call view, several screen shares watched side by side: button on one of them that shows it big with the others small beside it");

  static String get multiStreamSideBySide => Intl.message("Side by side",
      name: "multiStreamSideBySide",
      desc:
          "Call view, one screen share shown big with others small beside it: button that goes back to showing them all the same size");

  /// How many streams can be big at once.
  static const int most = 4;

  /// The streams shown big besides the call view's main one, oldest first.
  final List<VoipStream> others = [];

  /// The main stream is big and [others] are small beside it.
  bool pinned = false;

  /// Streams that went away (a sharer switching what they share), to put
  /// back when their sharer's new stream comes.
  final List<(String, VoipStreamType)> _follows = [];

  static bool _isWatchedShare(VoipSession session, VoipStream? stream) {
    if (stream == null ||
        stream.type != VoipStreamType.screenshare ||
        stream.direction != VoipStreamDirection.incoming) {
      return false;
    }
    return VoipStreamWatching.of(session)?.isWatching(stream) ?? false;
  }

  bool get isMulti => others.isNotEmpty;

  void clear() {
    others.clear();
    _follows.clear();
    pinned = false;
  }

  /// [stream] is to be shown big while [main] is: the new main stream.
  /// Screen shares you watch join the ones already big; anything else
  /// replaces them all.
  VoipStream? add(VoipSession session, VoipStream? main, VoipStream? stream) {
    if (stream == null) {
      clear();
      return null;
    }
    if (stream == main || others.contains(stream)) return main;
    if (!_isWatchedShare(session, stream) || !_isWatchedShare(session, main)) {
      clear();
      return stream;
    }
    others.add(stream);
    while (others.length > most - 1) {
      others.removeAt(0);
    }
    return main;
  }

  /// [stream] stops being big (you stopped watching it or popped it out):
  /// the new main stream.
  VoipStream? remove(VoipStream? main, VoipStream stream) {
    if (stream != main) {
      others.remove(stream);
    } else {
      main = others.isEmpty ? null : others.removeAt(0);
    }
    if (others.isEmpty) pinned = false;
    return main;
  }

  /// Shows [stream] big with the others beside it: the new main stream.
  VoipStream? showBig(VoipStream? main, VoipStream stream) {
    pinned = true;
    final i = others.indexOf(stream);
    if (i < 0 || main == null) return main;
    others[i] = main;
    return stream;
  }

  /// Keeps up with the call's streams: streams that went drop out (and come
  /// back with their sharer's next one), and ones you stopped watching
  /// drop out. Returns the new main stream.
  VoipStream? follow(VoipSession session, VoipStream? main) {
    if (others.isEmpty && _follows.isEmpty) return main;
    final streams = session.streams;
    if (main != null && others.isNotEmpty && !streams.contains(main)) {
      _follows.add((main.streamUserId, main.type));
      main = null;
    }
    for (final s in others.toList()) {
      if (!streams.contains(s)) {
        _follows.add((s.streamUserId, s.type));
        others.remove(s);
      } else if (!_isWatchedShare(session, s)) {
        others.remove(s);
      }
    }
    for (final f in _follows.toList()) {
      final s = streams
          .where((s) => s.streamUserId == f.$1 && s.type == f.$2)
          .firstOrNull;
      if (s == null) continue;
      _follows.remove(f);
      if (_isWatchedShare(session, s) && s != main && !others.contains(s)) {
        if (main == null) {
          main = s;
        } else {
          others.add(s);
        }
      }
    }
    if (others.isNotEmpty &&
        (main == null || !_isWatchedShare(session, main))) {
      main = others.removeAt(0);
    }
    if (others.isEmpty) pinned = false;
    return main;
  }
}

/// Vommet: the streams shown big, laid out side by side ([tile] builds each
/// one with its controls), or [main] big with the others small beside it
/// when [MultiStreamFocus.pinned]; tapping a small one shows it big
/// ([onShowBig]).
class MultiStreamLayout extends StatelessWidget {
  const MultiStreamLayout(
      {required this.focus,
      required this.main,
      required this.session,
      required this.tile,
      required this.onShowBig,
      super.key});

  final MultiStreamFocus focus;
  final VoipStream main;
  final VoipSession session;
  final Widget Function(VoipStream stream) tile;
  final void Function(VoipStream stream) onShowBig;

  static const double _gap = 4;

  Widget _cell(Widget child) =>
      Expanded(child: Padding(padding: const EdgeInsets.all(2), child: child));

  @override
  Widget build(BuildContext context) {
    final streams = [main, ...focus.others];
    return LayoutBuilder(builder: (context, constraints) {
      final w = constraints.maxWidth;
      final h = constraints.maxHeight;
      final wide = w / h > 1.2;
      if (focus.pinned) return _pinned(context, w, h, wide && w > 700);
      if (streams.length == 2) {
        final cells = streams.map((s) => _cell(tile(s))).toList();
        return wide ? Row(children: cells) : Column(children: cells);
      }
      // Three or four: a 2x2.
      Widget row(List<VoipStream> r) => _cell(Row(children: [
            for (final s in r) _cell(tile(s)),
            if (r.length == 1) const Spacer(),
          ]));
      return Column(children: [
        row(streams.sublist(0, 2)),
        row(streams.sublist(2)),
      ]);
    });
  }

  Widget _pinned(BuildContext context, double w, double h, bool side) {
    final small = [
      for (final s in focus.others)
        _SmallStream(
            key: ValueKey("multiStream_small_${s.streamId}"),
            stream: s,
            session: session,
            onTap: () => onShowBig(s)),
    ];
    final big = Padding(padding: const EdgeInsets.all(2), child: tile(main));
    if (side) {
      return Row(children: [
        Expanded(child: big),
        SizedBox(
          width: (w * .22).clamp(160, 280).toDouble(),
          child: ListView(padding: const EdgeInsets.all(2), children: [
            for (final s in small)
              Padding(
                padding: const EdgeInsets.only(bottom: _gap),
                child: AspectRatio(aspectRatio: 16 / 9, child: s),
              ),
          ]),
        ),
      ]);
    }
    return Column(children: [
      Expanded(child: big),
      SizedBox(
        height: (h * .22).clamp(72, 150).toDouble(),
        child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(2),
            children: [
              for (final s in small)
                Padding(
                  padding: const EdgeInsets.only(right: _gap),
                  child: AspectRatio(aspectRatio: 16 / 9, child: s),
                ),
            ]),
      ),
    ]);
  }
}

class _SmallStream extends StatelessWidget {
  const _SmallStream(
      {required this.stream,
      required this.session,
      required this.onTap,
      super.key});

  final VoipStream stream;
  final VoipSession session;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: MultiStreamFocus.multiStreamShowBig,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Stack(fit: StackFit.expand, children: [
            IgnorePointer(
              child: VoipStreamView(stream, session,
                  canFullscreen: false,
                  fit: BoxFit.contain,
                  key: ValueKey("multiStream_view_${stream.streamId}")),
            ),
            const Positioned(left: 6, top: 6, child: StreamLivePill(size: 8)),
          ]),
        ),
      ),
    );
  }
}
