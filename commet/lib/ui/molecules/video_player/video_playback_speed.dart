import 'package:commet/debug/log.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'video_player_controller.dart';

String get videoPlaybackSpeedTooltip => Intl.message("Playback speed",
    name: "videoPlaybackSpeedTooltip",
    desc: "Tooltip for the video player's playback speed button");

String videoPlaybackSpeedLabel(double speed) =>
    "${speed == speed.roundToDouble() ? speed.toInt() : speed}x";

/// The same click/tap menu in inline videos, the viewer, and picture-in-picture.
class VideoPlaybackSpeedButton extends StatelessWidget {
  const VideoPlaybackSpeedButton(
      {required this.controller, this.onMenuStateChanged, super.key});

  final VideoPlayerController controller;
  final ValueChanged<bool>? onMenuStateChanged;

  @override
  Widget build(BuildContext context) => StreamBuilder<double>(
        stream: controller.onPlaybackSpeedChanged,
        initialData: controller.playbackSpeed,
        builder: (context, snapshot) {
          final speed = snapshot.data ?? controller.playbackSpeed;
          final colors = Theme.of(context).colorScheme;
          return Material(
            type: MaterialType.transparency,
            child: PopupMenuButton<double>(
              key: const ValueKey("video_playback_speed_button"),
              tooltip: videoPlaybackSpeedTooltip,
              initialValue: speed,
              position: PopupMenuPosition.over,
              menuPadding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 100, maxWidth: 112),
              onOpened: () => onMenuStateChanged?.call(true),
              onCanceled: () => onMenuStateChanged?.call(false),
              onSelected: (value) async {
                onMenuStateChanged?.call(false);
                try {
                  await controller.setPlaybackSpeed(value);
                } catch (error, stack) {
                  Log.onError(error, stack,
                      content: "Couldn't change video playback speed");
                }
              },
              itemBuilder: (context) => [
                for (final value in [2.0, 1.5, 1.0, 0.5])
                  PopupMenuItem<double>(
                    value: value,
                    padding: EdgeInsets.zero,
                    child: Semantics(
                      selected: value == speed,
                      child: ColoredBox(
                        color: value == speed
                            ? colors.primaryContainer
                            : Colors.transparent,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 48),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Row(children: [
                              Expanded(
                                child: Text(videoPlaybackSpeedLabel(value),
                                    style: TextStyle(
                                        color: value == speed
                                            ? colors.onPrimaryContainer
                                            : colors.onSurface,
                                        fontWeight: value == speed
                                            ? FontWeight.w600
                                            : FontWeight.normal)),
                              ),
                              if (value == speed)
                                Icon(Icons.check,
                                    size: 18, color: colors.onPrimaryContainer),
                            ]),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 40, minHeight: 48),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Center(
                    widthFactor: 1,
                    heightFactor: 1,
                    child: Text(videoPlaybackSpeedLabel(speed),
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            height: 1)),
                  ),
                ),
              ),
            ),
          );
        },
      );
}
