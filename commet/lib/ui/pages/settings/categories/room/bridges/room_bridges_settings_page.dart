import 'package:commet/client/matrix/matrix_mxc_image_provider.dart';
import 'package:commet/utils/bridged_user_rules.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:tiamat/tiamat.dart' as tiamat;

/// Vommet: room settings › Bridges, like Element's: the bridges this room is
/// connected to, read from `m.bridge` (MSC2346) and its older name
/// `uk.half-shot.bridge`.

/// One part of a bridge event: its protocol, network or channel.
class RoomBridgePart {
  const RoomBridgePart({this.id, this.displayName, this.avatarUrl, this.url});

  final String? id;
  final String? displayName;
  final Uri? avatarUrl;
  final Uri? url;

  /// The display name, else the id.
  String? get label => displayName ?? id;

  static RoomBridgePart? parse(Object? content) {
    if (content is! Map) return null;
    String? str(String key) {
      final v = content[key];
      return v is String && v.trim().isNotEmpty ? v.trim() : null;
    }

    Uri? uri(String key) {
      final s = str(key);
      return s == null ? null : Uri.tryParse(s);
    }

    final part = RoomBridgePart(
        id: str("id"),
        displayName: str("displayname"),
        avatarUrl: uri("avatar_url"),
        url: uri("external_url"));
    return part.label == null ? null : part;
  }
}

/// A bridge listed in the room's state.
class RoomBridgeInfo {
  const RoomBridgeInfo({
    required this.stateKey,
    required this.protocol,
    this.network,
    this.channel,
    this.bridgeBot,
    this.creator,
  });

  final String stateKey;
  final RoomBridgePart protocol;
  final RoomBridgePart? network;
  final RoomBridgePart? channel;
  final String? bridgeBot;
  final String? creator;
}

/// The bridges in [states] (event type → state key → content), newest name
/// first: an `m.bridge` and a `uk.half-shot.bridge` with the same state key
/// are one bridge. Events without a protocol are left out.
List<RoomBridgeInfo> parseRoomBridges(
    Map<String, Map<String, Map<String, Object?>>> states) {
  final result = <RoomBridgeInfo>[];
  final seen = <String>{};
  for (final type in bridgeStateTypes) {
    final events = states[type];
    if (events == null) continue;
    final keys = events.keys.toList()..sort();
    for (final key in keys) {
      if (seen.contains(key)) continue;
      final content = events[key]!;
      final protocol = RoomBridgePart.parse(content["protocol"]);
      if (protocol == null) continue;
      String? str(String k) {
        final v = content[k];
        return v is String && v.isNotEmpty ? v : null;
      }

      seen.add(key);
      result.add(RoomBridgeInfo(
        stateKey: key,
        protocol: protocol,
        network: RoomBridgePart.parse(content["network"]),
        channel: RoomBridgePart.parse(content["channel"]),
        bridgeBot: str("bridgebot"),
        creator: str("creator"),
      ));
    }
  }
  return result;
}

/// The bridges in a Matrix room's state.
List<RoomBridgeInfo> matrixRoomBridges(matrix.Room room) => parseRoomBridges({
      for (final type in bridgeStateTypes)
        if (room.states[type] case final events?)
          type: {
            for (final e in events.entries)
              if (e.value.content.isNotEmpty) e.key: e.value.content
          },
    });

/// The Bridges tab for a Matrix room.
class MatrixRoomBridgesSettingsPage extends StatelessWidget {
  const MatrixRoomBridgesSettingsPage(this.room, {super.key});

  final matrix.Room room;

  @override
  Widget build(BuildContext context) {
    return RoomBridgesSettingsView(
      matrixRoomBridges(room),
      avatar: (uri) => uri.scheme == "mxc"
          ? MatrixMxcImage(uri, room.client, doThumbnail: true)
          : null,
    );
  }
}

class RoomBridgesSettingsView extends StatelessWidget {
  const RoomBridgesSettingsView(this.bridges, {this.avatar, super.key});

  final List<RoomBridgeInfo> bridges;
  final ImageProvider? Function(Uri avatarUrl)? avatar;

  static String get labelRoomBridgesExplanation => Intl.message(
      "This room is bridged to the following platforms: messages sent here "
      "are copied there, and the other way round.",
      name: "labelRoomBridgesExplanation",
      desc: "Top of the room settings tab listing the room's bridges");

  static String labelRoomBridgeChannel(String channel) =>
      Intl.message("Channel: $channel",
          args: [channel],
          name: "labelRoomBridgeChannel",
          desc: "The channel on the other platform a bridge connects to");

  static String labelRoomBridgeNetwork(String network) =>
      Intl.message("Network: $network",
          args: [network],
          name: "labelRoomBridgeNetwork",
          desc: "The server, workspace or network a bridged channel is in");

  static String labelRoomBridgeBot(String bot) =>
      Intl.message("Managed by $bot",
          args: [bot],
          name: "labelRoomBridgeBot",
          desc: "The Matrix account (bridge bot) that runs a bridge");

  static String labelRoomBridgeCreator(String creator) =>
      Intl.message("Set up by $creator",
          args: [creator],
          name: "labelRoomBridgeCreator",
          desc: "Who connected the room to the bridge");

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      spacing: 12,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(labelRoomBridgesExplanation,
              style: theme.textTheme.bodyMedium),
        ),
        for (final bridge in bridges) bridgeTile(context, bridge),
      ],
    );
  }

  Widget bridgeTile(BuildContext context, RoomBridgeInfo bridge) {
    final theme = Theme.of(context);
    final low = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final protocolAvatar = bridge.protocol.avatarUrl;
    final channelAvatar = bridge.channel?.avatarUrl;
    return tiamat.Panel(
      mode: tiamat.TileType.surfaceContainerLow,
      mainAxisSize: MainAxisSize.min,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            tiamat.Avatar.medium(
              image:
                  protocolAvatar == null ? null : avatar?.call(protocolAvatar),
              placeholderText: bridge.protocol.label,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 2,
                children: [
                  Text(bridge.protocol.label!,
                      style: theme.textTheme.titleMedium),
                  if (bridge.channel?.label case final channel?)
                    Row(
                      children: [
                        if (channelAvatar != null)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: tiamat.Avatar.small(
                              image: avatar?.call(channelAvatar),
                              placeholderText: channel,
                            ),
                          ),
                        Flexible(
                          child: Text(labelRoomBridgeChannel(channel),
                              style: theme.textTheme.bodyMedium),
                        ),
                      ],
                    ),
                  if (bridge.network?.label case final network?)
                    Text(labelRoomBridgeNetwork(network),
                        style: theme.textTheme.bodyMedium),
                  if (bridge.bridgeBot case final bot?)
                    Text(labelRoomBridgeBot(bot), style: low),
                  if (bridge.creator case final creator?)
                    Text(labelRoomBridgeCreator(creator), style: low),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
