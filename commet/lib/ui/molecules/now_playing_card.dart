// Vommet: now-playing media controls (premium-free feature batch). What a
// music or video app on this computer is playing, above your name in the
// bottom-left corner: cover, title, artist and app, how far along it is,
// and previous / play-pause / next where the app has them. Click it to bring
// the app to the front; dots switch between apps when several have
// something loaded. Linux only, behind the "Now playing controls"
// experiment (utils/now_playing/now_playing.dart).
import 'dart:async';
import 'dart:io';

import 'package:commet/utils/voice_message.dart';
import 'package:commet/utils/now_playing/now_playing.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

String get nowPlayingPlay => Intl.message("Play",
    name: "nowPlayingPlay",
    desc: "Now playing controls: tooltip on the button that resumes the track");

String get nowPlayingPause => Intl.message("Pause",
    name: "nowPlayingPause",
    desc: "Now playing controls: tooltip on the button that pauses the track");

String get nowPlayingPrevious => Intl.message("Previous track",
    name: "nowPlayingPrevious",
    desc: "Now playing controls: tooltip on the previous track button");

String get nowPlayingNext => Intl.message("Next track",
    name: "nowPlayingNext",
    desc: "Now playing controls: tooltip on the next track button");

String get nowPlayingSwitchApp => Intl.message("Show this app's track",
    name: "nowPlayingSwitchApp",
    desc:
        "Now playing controls: tooltip on a dot that switches to another media app's track");

class NowPlayingCard extends StatefulWidget {
  const NowPlayingCard({this.compact = false, super.key});

  /// Under the room list collapsed to pictures: just play / pause.
  final bool compact;

  @override
  State<NowPlayingCard> createState() => _NowPlayingCardState();
}

class _NowPlayingCardState extends State<NowPlayingCard> {
  late final List<StreamSubscription> _subs;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    NowPlaying.instance.start();
    _subs = [
      NowPlaying.instance.onChanged.listen((_) => _changed()),
      experimentNowPlaying.onChanged.listen((_) => _changed()),
    ];
    _changed(rebuild: false);
  }

  @override
  void dispose() {
    for (final sub in _subs) {
      sub.cancel();
    }
    _tick?.cancel();
    super.dispose();
  }

  /// Rebuilds, and moves the progress bar each second while a track plays.
  void _changed({bool rebuild = true}) {
    final playing = NowPlaying.enabled &&
        (NowPlaying.instance.current?.playing ?? false) &&
        !widget.compact;
    if (playing && _tick == null) {
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!playing) {
      _tick?.cancel();
      _tick = null;
    }
    if (rebuild && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (!NowPlaying.enabled) return const SizedBox.shrink();
    final player = NowPlaying.instance.current;
    if (player == null) return const SizedBox.shrink();
    if (widget.compact) {
      if (!player.canPlayPause) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Tooltip(
          message: "${player.title} · ${player.app}",
          child: _button(
              key: const ValueKey("now-playing-play-pause"),
              icon: player.playing ? Icons.pause : Icons.play_arrow,
              tooltip: null,
              onPressed: () => NowPlaying.instance.playPause(player.busName)),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
      child: _card(context, player),
    );
  }

  Widget _card(BuildContext context, NowPlayingPlayer player) {
    final scheme = ColorScheme.of(context);
    final text = TextTheme.of(context);
    final players = NowPlaying.instance.players;
    final length = player.length;
    final position = player.positionAtTime(DateTime.now());
    final subtitle = [
      if (player.artist.isNotEmpty) player.artist,
      player.app,
    ].join(" · ");
    return Material(
      key: const ValueKey("now-playing-card"),
      color: scheme.surfaceTint.withAlpha(10),
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: player.canRaise
            ? () => NowPlaying.instance.raise(player.busName)
            : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 6, 2, 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 4,
            children: [
              Row(
                spacing: 8,
                children: [
                  _cover(context, player),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(player.title ?? "",
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.labelLarge),
                        Text(subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.labelSmall?.copyWith(
                                fontSize: 11, color: scheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  if (player.canPrevious)
                    _button(
                        icon: Icons.skip_previous,
                        tooltip: nowPlayingPrevious,
                        onPressed: () =>
                            NowPlaying.instance.previous(player.busName)),
                  if (player.canPlayPause)
                    _button(
                        key: const ValueKey("now-playing-play-pause"),
                        icon: player.playing ? Icons.pause : Icons.play_arrow,
                        tooltip:
                            player.playing ? nowPlayingPause : nowPlayingPlay,
                        onPressed: () =>
                            NowPlaying.instance.playPause(player.busName)),
                  if (player.canNext)
                    _button(
                        icon: Icons.skip_next,
                        tooltip: nowPlayingNext,
                        onPressed: () =>
                            NowPlaying.instance.next(player.busName)),
                ],
              ),
              if (length != null)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Row(
                    spacing: 6,
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value: length.inMilliseconds == 0
                                ? 0
                                : position.inMilliseconds /
                                    length.inMilliseconds,
                            minHeight: 3,
                            color: scheme.primary,
                            backgroundColor: scheme.onSurface.withAlpha(30),
                          ),
                        ),
                      ),
                      Text(
                          "${VoiceMessage.formatDuration(position)} / "
                          "${VoiceMessage.formatDuration(length)}",
                          style: text.labelSmall?.copyWith(
                              fontSize: 10,
                              color: scheme.onSurfaceVariant,
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ])),
                    ],
                  ),
                ),
              if (players.length > 1)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (final p in players)
                      Tooltip(
                        message: "${p.app}: ${p.title}",
                        child: InkWell(
                          key: ValueKey("now-playing-dot-${p.busName}"),
                          customBorder: const CircleBorder(),
                          onTap: () => NowPlaying.instance.choose(p.busName),
                          child: Padding(
                            padding: const EdgeInsets.all(3),
                            child: Semantics(
                              button: true,
                              label: nowPlayingSwitchApp,
                              child: Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: p.busName == player.busName
                                      ? scheme.onSurface
                                      : scheme.onSurface.withAlpha(70),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cover(BuildContext context, NowPlayingPlayer player) {
    final scheme = ColorScheme.of(context);
    final fallback = Container(
      color: scheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Icon(Icons.music_note, size: 20, color: scheme.onSurfaceVariant),
    );
    final art = player.art;
    Widget image = fallback;
    if (art != null) {
      Widget error(BuildContext _, Object __, StackTrace? ___) => fallback;
      image = art.scheme == "file"
          ? Image.file(File(art.toFilePath()),
              fit: BoxFit.cover, errorBuilder: error)
          : Image.network(art.toString(),
              fit: BoxFit.cover, errorBuilder: error);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(width: 36, height: 36, child: image),
    );
  }

  Widget _button(
          {Key? key,
          required IconData icon,
          required String? tooltip,
          required VoidCallback onPressed}) =>
      IconButton(
        key: key,
        icon: Icon(icon, size: 20),
        tooltip: tooltip,
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
        onPressed: onPressed,
      );
}
