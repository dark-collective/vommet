// Vommet: feeds the unified chat list (Vommet issue 291) from the clients.
//
// Turns rooms, DMs and spaces into the models in unified_chat_model.dart and
// rebuilds them, coalesced, when anything they show changes. Building the
// models only reads what the SDK already holds in memory (each room's last
// event and unread counts arrive with sync, sliding sync too); member
// lookups for sender names happen later, only for rows on screen.
import 'dart:async';

import 'package:commet/client/alert.dart';
import 'package:commet/client/client.dart';
import 'package:commet/client/client_manager.dart';
import 'package:commet/client/components/direct_messages/direct_message_component.dart';
import 'package:commet/client/components/invitation/invitation.dart';
import 'package:commet/client/components/invitation/invitation_component.dart';
import 'package:commet/client/components/voip_room/voip_room_component.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/matrix_space.dart';
import 'package:commet/client/room_preview.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/ui/organisms/unified_chat_list/unified_chat_model.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:flutter/foundation.dart';

/// Account data holding the rooms pinned to the sidebar (written by the
/// "Pin rooms to the sidebar" experiment): {"rooms": {roomId: {"order"}}}.
const pinnedRoomsAccountDataKey = "im.nether.chat.sidebar_rooms";

/// Reads the pinned rooms from that account data: room id -> saved order.
Map<String, String?> readPinnedRooms(Object? content) {
  if (content is! Map) return const {};
  final rooms = content["rooms"];
  if (rooms is! Map) return const {};
  return {
    for (final entry in rooms.entries)
      if (entry.key is String)
        entry.key as String: switch (entry.value) {
          {"order": String order} => order,
          _ => null,
        },
  };
}

class UnifiedChatSource extends ChangeNotifier {
  UnifiedChatSource(this.clientManager, {Client? filterClient})
      : _filterClient = filterClient {
    _subs = [
      clientManager.onRoomUpdated.stream.listen(_changed),
      clientManager.onSpaceUpdated.stream.listen(_changed),
      clientManager.onSpaceChildUpdated.stream.listen(_changed),
      clientManager.onSpaceAdded.listen(_changed),
      clientManager.onSpaceRemoved.listen(_changed),
      clientManager.rooms.onListUpdated.listen(_changed),
      clientManager.directMessages.directMessageRooms.onListUpdated
          .listen(_changed),
      clientManager.onDirectMessageRoomUpdated.stream.listen(_changed),
      clientManager.onClientAdded.stream.listen(_clientsChanged),
      clientManager.onClientRemoved.stream.listen(_clientsChanged),
      clientManager.alertManager.onAlertAdded.listen(_changed),
      clientManager.alertManager.onAlertRemoved.listen(_changed),
      // Pins live in account data, which arrives with sync.
      clientManager.onSync.stream.listen(_changed),
      EventBus.setFilterClient.stream.listen(setFilterClient),
    ];
    _watchInvitations();
    _rebuild();
  }

  final ClientManager clientManager;
  Client? _filterClient;
  late final List<StreamSubscription> _subs;
  final List<StreamSubscription> _invitationSubs = [];
  final Map<String, StreamSubscription> _voiceSubs = {};
  final Set<String> _loadingSpaces = {};
  Timer? _pending;
  bool _disposed = false;

  List<TopRow> _rows = const [];
  Map<String, SpaceEntry> _spaces = const {};
  List<(Client, Invitation)> _invitations = const [];

  /// Alerts dismissed in this session (they stay in the alert manager).
  static final Set<Alert> _dismissedAlerts = {};

  List<TopRow> get rows => _rows;

  /// Top-level spaces and every subspace below them, by key.
  Map<String, SpaceEntry> get spaces => _spaces;

  List<(Client, Invitation)> get invitations => _invitations;

  List<Alert> get alerts => clientManager.alertManager.alerts
      .where((a) => !_dismissedAlerts.contains(a))
      .toList(growable: false);

  void dismissAlert(Alert alert) {
    _dismissedAlerts.add(alert);
    notifyListeners();
  }

  void setFilterClient(Client? client) {
    _filterClient = client;
    _rebuild();
  }

  bool _included(Client client) =>
      _filterClient == null || client == _filterClient;

  void _clientsChanged(Object? _) {
    _watchInvitations();
    _changed(null);
  }

  void _watchInvitations() {
    for (final sub in _invitationSubs) {
      sub.cancel();
    }
    _invitationSubs.clear();
    for (final client in clientManager.clients) {
      final comp = client.getComponent<InvitationComponent>();
      if (comp != null) {
        _invitationSubs.add(comp.invitations.onListUpdated.listen(_changed));
      }
    }
  }

  /// Coalesces bursts (a sync touches many rooms at once) into one rebuild.
  void _changed(Object? _) {
    if (_disposed || _pending != null) return;
    _pending = Timer(const Duration(milliseconds: 150), () {
      _pending = null;
      _rebuild();
    });
  }

  /// Rebuilds now, e.g. after loading a space's unjoined rooms.
  void refresh() => _changed(null);

  void _rebuild() {
    if (_disposed) return;
    try {
      _build();
    } catch (e, s) {
      Log.onError(e, s);
    }
    notifyListeners();
  }

  void _build() {
    final clients =
        clientManager.clients.where(_included).toList(growable: false);

    final voiceRooms = <String, Room>{};
    final pins = <String, String?>{};
    final directs = <ChatEntry>[];
    final singles = <ChatEntry>[];
    final topSpaces = <SpaceEntry>[];
    final allSpaces = <String, SpaceEntry>{};

    for (final client in clients) {
      pins.addAll(_pinsOf(client));
      final dms = client.getComponent<DirectMessagesComponent>();

      for (final room in client.rooms) {
        final direct = dms?.isRoomDirectMessage(room) == true;
        final entry = chatEntryOf(room, direct: direct, voiceRooms: voiceRooms);
        (direct ? directs : singles).add(entry);
      }

      for (final space in client.spaces.where((s) => s.isTopLevel)) {
        final entry = _spaceEntryOf(space, voiceRooms, {});
        topSpaces.add(entry);
        for (final s in entry.allSpaces) {
          allSpaces[s.key] = s;
        }
      }
    }

    _rows = buildTopRows(
        directMessages: directs, rooms: singles, spaces: topSpaces, pins: pins);
    _spaces = allSpaces;

    _invitations = [
      for (final client in clients)
        for (final invite
            in client.getComponent<InvitationComponent>()?.invitations ??
                const <Invitation>[])
          (client, invite),
    ];

    _watchVoice(voiceRooms);
  }

  Map<String, String?> _pinsOf(Client client) {
    if (client is! MatrixClient) return const {};
    try {
      return readPinnedRooms(
          client.matrixClient.accountData[pinnedRoomsAccountDataKey]?.content);
    } catch (e, s) {
      Log.onError(e, s);
      return const {};
    }
  }

  /// Follows who's in each voice room, so a space's "N in voice" line
  /// updates when someone joins or leaves.
  void _watchVoice(Map<String, Room> rooms) {
    _voiceSubs.removeWhere((key, sub) {
      if (rooms.containsKey(key)) return false;
      sub.cancel();
      return true;
    });
    for (final entry in rooms.entries) {
      if (_voiceSubs.containsKey(entry.key)) continue;
      final voip = entry.value.getComponent<VoipRoomComponent>();
      if (voip != null) {
        _voiceSubs[entry.key] = voip.onParticipantsChanged.listen(_changed);
      }
    }
  }

  SpaceEntry _spaceEntryOf(
      Space space, Map<String, Room> voiceRooms, Set<String> visiting) {
    visiting.add(space.localId);

    int? members;
    if (space is MatrixSpace) {
      members = space.matrixRoom.summary.mJoinedMemberCount;
    }

    return SpaceEntry(
      key: space.localId,
      spaceId: space.identifier,
      name: space.displayName,
      rooms: [
        for (final room in space.rooms)
          chatEntryOf(room,
              direct: room.client
                      .getComponent<DirectMessagesComponent>()
                      ?.isRoomDirectMessage(room) ==
                  true,
              voiceRooms: voiceRooms),
      ],
      subspaces: [
        for (final sub in space.subspaces)
          // A space hierarchy can loop; stop where it comes back.
          if (!visiting.contains(sub.localId))
            _spaceEntryOf(sub, voiceRooms, {...visiting}),
      ],
      previews: [
        for (final preview in space.childPreviews)
          if (preview.type != RoomType.space) previewEntryOf(preview),
      ],
      memberCount: members,
      muted: space.pushRule != PushRule.notify,
      avatar: space.avatar,
      color: space.color,
      source: space,
    );
  }

  /// Loads a space's rooms we haven't joined (once), for its pane.
  void ensureSpaceLoaded(String key) {
    final space = _spaces[key]?.source;
    if (space is! Space || space.fullyLoaded || !_loadingSpaces.add(key)) {
      return;
    }
    space
        .loadExtra()
        .then((_) => refresh())
        .catchError((Object e, StackTrace s) {
      Log.onError(e, s);
      _loadingSpaces.remove(key);
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _pending?.cancel();
    for (final sub in [..._subs, ..._invitationSubs, ..._voiceSubs.values]) {
      sub.cancel();
    }
    super.dispose();
  }
}

ChatEntry chatEntryOf(Room room,
    {required bool direct, Map<String, Room>? voiceRooms}) {
  final voip = room.getComponent<VoipRoomComponent>();
  if (voip != null) voiceRooms?[room.localId] = room;

  final participants = voip?.getCurrentParticipants() ?? const <String>[];
  final timestamp = room.lastEventTimestamp;

  return ChatEntry(
    key: room.localId,
    roomId: room.identifier,
    name: room.displayName,
    kind: direct
        ? ChatKind.direct
        : (voip != null ? ChatKind.voice : ChatKind.room),
    lastActivity: timestamp.millisecondsSinceEpoch == 0 ? null : timestamp,
    sender: () => _senderOf(room, direct),
    preview: room.lastMessage?.plainTextBody,
    unread: room.notificationCount,
    mentions: room.displayHighlightedNotificationCount,
    muted: room.pushRule != PushRule.notify,
    voiceCount: participants.length,
    voiceNames: participants.isEmpty
        ? null
        : () => [
              for (final id in participants)
                room.getMemberOrFallback(id).displayName
            ],
    avatar: room.avatar,
    color: room.defaultColor,
    source: room,
  );
}

String? _senderOf(Room room, bool direct) {
  final sender = room.lastMessage?.senderId;
  if (sender == null) return null;
  if (sender == room.client.self?.identifier) return "You";
  if (direct) return null;
  return room.getMemberOrFallback(sender).displayName;
}

ChatPreviewEntry previewEntryOf(RoomPreview preview) => ChatPreviewEntry(
      roomId: preview.roomId,
      name: preview.displayName,
      isVoice: preview.type == RoomType.voipRoom,
      memberCount: preview.numMembers,
      source: preview,
    );

/// Whether [path] still names a top-level space of [rows] followed by a
/// chain of subspaces, each inside the one before.
bool isValidSpacePath(List<TopRow> rows, List<String> path) {
  if (path.isEmpty) return false;
  final top = rows
      .whereType<SpaceTopRow>()
      .where((row) => row.key == path.first)
      .firstOrNull;
  if (top == null) return false;
  SpaceEntry space = top.space;
  for (final key in path.skip(1)) {
    final next = space.subspaces.where((s) => s.key == key).firstOrNull;
    if (next == null) return false;
    space = next;
  }
  return true;
}
