// Vommet (New Home cards, round 4): the Live calls card. Every room with a
// call going on, not only your contacts' (that's Active Now): who's in it,
// how long it has run, and Join. Its settings, and the optional green dot
// on the rail's Home button. Which rooms, in what order: the pure
// new_home_live_calls_model.dart.
import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/client/client_manager.dart';
import 'package:commet/client/member.dart';
import 'package:commet/client/components/room_call/room_call_component.dart';
import 'package:commet/client/components/voip_room/voip_room_component.dart';
import 'package:commet/client/matrix/components/voip_room/matrix_rtc_membership.dart';
import 'package:commet/client/matrix/components/voip_room/matrix_voip_room_component.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/molecules/room_call_bar.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/ui/organisms/new_home/new_home.dart';
import 'package:commet/ui/organisms/new_home/new_home_cards.dart';
import 'package:commet/ui/organisms/new_home/new_home_column.dart';
import 'package:commet/ui/organisms/new_home/new_home_editor.dart';
import 'package:commet/ui/organisms/new_home/new_home_layout.dart';
import 'package:commet/ui/organisms/new_home/new_home_live_calls_model.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:tiamat/tiamat.dart' as tiamat;

/// Who's in [room]'s call: a voice room's members in it, or another room's
/// call when room calls are on (otherwise its Join couldn't work).
List<String> liveCallParticipants(Room room) {
  final voip = room.getComponent<VoipRoomComponent>();
  if (voip != null) return voip.getCurrentParticipants();
  if (!RoomCallActions.usesRoomCalls(room)) return const [];
  return room.getComponent<RoomCallComponent>()?.getCurrentParticipants() ??
      const [];
}

/// When [room]'s call began: its oldest live membership's `created_ts`.
DateTime? liveCallStartedAt(Room room) {
  if (room is! MatrixRoom) return null;
  final state =
      room.matrixRoom.states[MatrixVoipRoomComponent.callMemberStateEvent];
  if (state == null) return null;
  final now = DateTime.now().millisecondsSinceEpoch;
  int? oldest;
  for (final event in state.values) {
    if (event is! matrix.Event) continue;
    final at = event.originServerTs.millisecondsSinceEpoch;
    if (!MatrixRtcMembership.isLive(event.content, at, now)) continue;
    final created = MatrixRtcMembership.createdTs(event.content, at);
    if (oldest == null || created < oldest) oldest = created;
  }
  return oldest == null ? null : DateTime.fromMillisecondsSinceEpoch(oldest);
}

bool isRoomMuted(Room room) => room.pushRule == PushRule.dontNotify;

bool isRoomLowPriority(Room room) =>
    room is MatrixRoom &&
    room.matrixRoom.tags[matrix.TagType.lowPriority] != null;

/// The calls a Live calls [card] shows, of [filterClient]'s rooms (every
/// account's when null).
List<LiveCall<Room>> liveCallsFor(
    ClientManager manager, HomeCard card, Client? filterClient) {
  final favourites = {
    for (final client in manager.clients) ...client.favoriteRooms
  };
  final space = card.callsIn == HomeCard.callsInSpace
      ? spaceOfCard(manager, card)?.roomsWithChildren.toSet() ?? const {}
      : const <Room>{};
  return liveCallsOf<Room>(
    [
      for (final room in manager.rooms)
        if ((filterClient == null || room.client == filterClient) &&
            !hiddenFromNewHome(room))
          room
    ],
    card,
    participants: liveCallParticipants,
    startedAt: liveCallStartedAt,
    isDirectMessage: isNewHomeDirectMessage,
    isMuted: isRoomMuted,
    isLowPriority: isRoomLowPriority,
    isFavourite: favourites.contains,
    inSpace: space.contains,
  );
}

/// Rebuilds on every sync (call memberships come with it) and each
/// half-minute (durations, memberships that lapse by time).
mixin _LiveCallsRefresh<T extends StatefulWidget> on State<T> {
  StreamSubscription? _sync;
  Timer? _tick;

  void startRefresh(ClientManager manager) {
    _sync = manager.onSync.stream.listen((_) {
      if (mounted) setState(() {});
    });
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _sync?.cancel();
    _tick?.cancel();
    super.dispose();
  }
}

/// The Live calls card's rows, or its one-line empty state.
class NewHomeLiveCallsCardBody extends StatefulWidget {
  const NewHomeLiveCallsCardBody(
      {super.key,
      required this.clientManager,
      required this.filterClient,
      required this.card});

  final ClientManager clientManager;
  final Client? filterClient;
  final HomeCard card;

  @override
  State<NewHomeLiveCallsCardBody> createState() => _LiveCallsCardState();
}

class _LiveCallsCardState extends State<NewHomeLiveCallsCardBody>
    with _LiveCallsRefresh {
  @override
  void initState() {
    super.initState();
    startRefresh(widget.clientManager);
  }

  @override
  Widget build(BuildContext context) {
    final calls =
        liveCallsFor(widget.clientManager, widget.card, widget.filterClient);
    if (calls.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
        child: tiamat.Text.labelLow(
            "No calls right now. Calls in your rooms show up here."),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final call in calls)
          LiveCallRow(call,
              key: ValueKey("NewHomeLiveCall-${call.room.localId}")),
      ],
    );
  }
}

/// One call: the room, who's in it and for how long, their avatars, Join.
/// Tapping the row opens the room.
class LiveCallRow extends StatelessWidget {
  const LiveCallRow(this.call, {super.key});
  final LiveCall<Room> call;

  Room get room => call.room;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final members = [
      for (final id in call.participants) room.getMemberOrFallback(id)
    ];
    final started = call.startedAt;
    final line = [
      callPeopleLine([for (final m in members) m.displayName]),
      if (started != null) callDurationLine(DateTime.now().difference(started)),
      if (isRoomMuted(room) || isRoomLowPriority(room)) "muted room",
    ].join(" · ");
    final inCall = clientManager?.callManager
            .getCallInRoom(room.client, room.identifier) !=
        null;
    return InkWell(
      mouseCursor: WidgetStateMouseCursor.clickable,
      borderRadius: BorderRadius.circular(10),
      onTap: () => openRoom(room),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(spacing: 10, children: [
          tiamat.Avatar(
            radius: 18,
            image: room.avatar,
            placeholderText: room.displayName,
            placeholderColor: room.defaultColor,
          ),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(room.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700)),
              Text(line,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12.5, color: scheme.onSurfaceVariant)),
            ]),
          ),
          _AvatarStack(members),
          inCall
              ? Text("In call",
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.green.shade400))
              : FilledButton.tonal(
                  key: ValueKey("NewHomeLiveCallJoin-${room.localId}"),
                  style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact),
                  onPressed: () => joinLiveCall(context, room),
                  child: const Text("Join"),
                ),
        ]),
      ),
    );
  }
}

class _AvatarStack extends StatelessWidget {
  const _AvatarStack(this.members);
  final List<Member> members;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const size = 22.0, step = 15.0;
    final shown = members.take(3).toList();
    final more = members.length - shown.length;
    final count = shown.length + (more > 0 ? 1 : 0);
    return SizedBox(
      width: size + step * (count - 1),
      height: size,
      child: Stack(children: [
        for (var i = 0; i < shown.length; i++)
          Positioned(
            left: step * i,
            child: Container(
              decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: scheme.surfaceContainer, width: 2)),
              child: tiamat.Avatar(
                radius: size / 2 - 2,
                image: shown[i].avatar,
                placeholderText: shown[i].displayName,
                placeholderColor: shown[i].defaultColor,
              ),
            ),
          ),
        if (more > 0)
          Positioned(
            left: step * shown.length,
            child: Container(
              width: size,
              height: size,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: scheme.surfaceContainerHighest,
                  border: Border.all(color: scheme.surfaceContainer, width: 2)),
              child: Text("+$more",
                  style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurfaceVariant)),
            ),
          ),
      ]),
    );
  }
}

void openRoom(Room room) => EventBus.doOpenRoom(room.identifier,
    clientId: room.client.identifier, openInSpace: false);

/// Join: opens the room and joins its call the way the room itself does (a
/// voice room's Join, or the Call button's checks for other rooms).
Future<void> joinLiveCall(BuildContext context, Room room) async {
  openRoom(room);
  final voip = room.getComponent<VoipRoomComponent>();
  if (voip != null) {
    if (!voip.canJoinCall || voip.currentSession != null) return;
    try {
      await voip.joinCall();
    } catch (e, s) {
      if (context.mounted) await AdaptiveDialog.showError(context, e, s);
    }
    return;
  }
  await RoomCallActions.joinOrStart(context, room, start: false);
}

/// The Live calls card's settings: which rooms, muted rooms, DM calls and
/// the green dot.
Future<void> editLiveCallsSettings(
    BuildContext context, ClientManager manager, HomeCard card) async {
  final next = await showDialog<HomeCard>(
    context: context,
    builder: (context) => LiveCallsSettingsDialog(manager: manager, card: card),
  );
  if (next == null) return;
  final store = HomeLayoutStore.instance;
  await store.save(store.layout.value.replace(next));
}

class LiveCallsSettingsDialog extends StatefulWidget {
  const LiveCallsSettingsDialog(
      {super.key, required this.manager, required this.card});
  final ClientManager manager;
  final HomeCard card;

  @override
  State<LiveCallsSettingsDialog> createState() =>
      _LiveCallsSettingsDialogState();
}

class _LiveCallsSettingsDialogState extends State<LiveCallsSettingsDialog> {
  late HomeCard card = widget.card;

  Future<void> pickOneSpace() async {
    final space = await pickSpace(context, widget.manager);
    if (space == null || !mounted) return;
    setState(() => card = card.copyWith(
        callsIn: HomeCard.callsInSpace,
        space: space.identifier,
        spaceClient: space.client.identifier));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final space = card.callsIn == HomeCard.callsInSpace
        ? spaceOfCard(widget.manager, card)
        : null;
    Widget toggle(String key, String label, bool value,
            HomeCard Function(bool v) change) =>
        CheckboxListTile(
          key: ValueKey(key),
          dense: true,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: value,
          onChanged: (v) => setState(() => card = change(v ?? false)),
          title: Text(label),
        );
    return Dialog(
      backgroundColor: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(spacing: 10, children: [
                const CardIcon(HomeLayout.liveCalls, size: 28),
                const Expanded(
                    child: Text("Live calls settings",
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w800))),
                IconButton(
                    tooltip: "Close",
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(context).pop()),
              ]),
              const SizedBox(height: 8),
              Text("SHOW CALLS IN",
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: scheme.onSurfaceVariant)),
              const SizedBox(height: 6),
              Wrap(spacing: 8, runSpacing: 8, children: [
                ChoiceChip(
                  mouseCursor: WidgetStateMouseCursor.clickable,
                  key: const ValueKey("NewHomeLiveCallsAll"),
                  label: const Text("All my rooms"),
                  selected: card.callsIn == HomeCard.callsInAll,
                  showCheckmark: false,
                  onSelected: (_) => setState(
                      () => card = card.copyWith(callsIn: HomeCard.callsInAll)),
                ),
                ChoiceChip(
                  mouseCursor: WidgetStateMouseCursor.clickable,
                  key: const ValueKey("NewHomeLiveCallsFavourites"),
                  label: const Text("Favorites"),
                  selected: card.callsIn == HomeCard.callsInFavourites,
                  showCheckmark: false,
                  onSelected: (_) => setState(() => card =
                      card.copyWith(callsIn: HomeCard.callsInFavourites)),
                ),
                ChoiceChip(
                  mouseCursor: WidgetStateMouseCursor.clickable,
                  key: const ValueKey("NewHomeLiveCallsSpace"),
                  label: Text(space == null
                      ? "One space"
                      : "One space: ${space.displayName}"),
                  selected: card.callsIn == HomeCard.callsInSpace,
                  showCheckmark: false,
                  onSelected: (_) => pickOneSpace(),
                ),
              ]),
              const SizedBox(height: 8),
              toggle("NewHomeLiveCallsMuted", "Include muted rooms",
                  card.includeMuted, (v) => card.copyWith(includeMuted: v)),
              toggle("NewHomeLiveCallsDms", "Include direct-message calls",
                  card.dms, (v) => card.copyWith(dms: v)),
              toggle("NewHomeLiveCallsDot", "Show the green dot on Home",
                  card.railDot, (v) => card.copyWith(railDot: v)),
              Text("Low-priority rooms follow \"Include muted rooms\".",
                  style: TextStyle(
                      fontSize: 12.5, color: scheme.onSurfaceVariant)),
              const SizedBox(height: 16),
              Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  spacing: 8,
                  children: [
                    TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text("Cancel")),
                    FilledButton(
                      key: const ValueKey("NewHomeLiveCallsSave"),
                      onPressed: card.callsIn == HomeCard.callsInSpace &&
                              card.space == null
                          ? null
                          : () => Navigator.of(context).pop(card),
                      child: const Text("Save"),
                    ),
                  ]),
            ],
          ),
        ),
      ),
    );
  }
}

/// Whether Home's layout has a Live calls card asking for the rail's green
/// dot (any tab, any view), and that card shows a call now.
bool liveCallDotShown(ClientManager manager) {
  if (!experimentNewHome.value) return false;
  for (final tab in HomeLayoutStore.instance.tabs.value.tabs) {
    for (final view in tab.views) {
      for (final card in view.main.visible) {
        if (card.type == HomeLayout.liveCalls &&
            card.railDot &&
            liveCallsFor(manager, card, null).isNotEmpty) {
          return true;
        }
      }
    }
  }
  return false;
}

/// The green dot on the rail's Home button while a call shows on a Live
/// calls card that asks for it (off by default).
class NewHomeLiveCallDot extends StatefulWidget {
  const NewHomeLiveCallDot({super.key});

  @override
  State<NewHomeLiveCallDot> createState() => _NewHomeLiveCallDotState();
}

class _NewHomeLiveCallDotState extends State<NewHomeLiveCallDot>
    with _LiveCallsRefresh {
  StreamSubscription? experiment;

  void changed() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    final manager = clientManager;
    if (manager != null) startRefresh(manager);
    HomeLayoutStore.instance.tabs.addListener(changed);
    experiment = experimentNewHome.onChanged.listen((_) => changed());
  }

  @override
  void dispose() {
    HomeLayoutStore.instance.tabs.removeListener(changed);
    experiment?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final manager = clientManager;
    if (manager == null || !liveCallDotShown(manager)) {
      return const SizedBox.shrink();
    }
    return Tooltip(
      message: "A call is going on",
      child: Container(
        key: const ValueKey("NewHomeLiveCallDot"),
        width: 12,
        height: 12,
        decoration: BoxDecoration(
            color: Colors.green.shade400,
            shape: BoxShape.circle,
            border: Border.all(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                width: 2)),
      ),
    );
  }
}
