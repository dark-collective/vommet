import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/client/components/activities/activities_component.dart';
import 'package:commet/client/components/voip/voip_session.dart';
import 'package:commet/client/components/voip/voip_stream.dart';
import 'package:commet/client/components/voip_room/voip_room_component.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/atoms/voice_room_occupancy.dart';
import 'package:flutter/material.dart';

/// Vommet: the call mark on a space's rail icon (experiment
/// `experiment_sidebar_subspace_guides`). Green headphones while anyone is
/// in a voice room in the space or its subspaces; a red LIVE pill instead
/// while someone shares their screen in a call there that you're in (other
/// calls' screen shares can't be known without joining them).
class SpaceCallBadge extends StatefulWidget {
  const SpaceCallBadge(this.space, {super.key});
  final Space space;

  @override
  State<SpaceCallBadge> createState() => _SpaceCallBadgeState();
}

/// Discord's red, in every theme (the theme's error colour is a pale pink
/// on dark themes): white text on it is 4.6:1.
const _liveRed = Color(0xffda373c);

class _SpaceCallBadgeState extends State<SpaceCallBadge> {
  final List<StreamSubscription> _roomSubs = [];
  final List<StreamSubscription> _callSubs = [];
  late final List<StreamSubscription> _subs;
  bool occupied = false;
  bool live = false;

  @override
  void initState() {
    super.initState();
    final calls = clientManager!.callManager;
    _subs = [
      // Rooms or subspaces added or removed.
      widget.space.onUpdate.listen((_) => _watchRooms()),
      calls.currentSessions.onListUpdated.listen((_) => _watchCalls()),
      preferences.onSettingChanged.listen((_) => _update()),
    ];
    _watchRooms();
    _watchCalls();
  }

  List<Room> get _voiceRooms => widget.space.roomsWithChildren
      .where((room) => room.getComponent<VoipRoomComponent>() != null)
      .toList();

  void _watchRooms() {
    for (final sub in _roomSubs) {
      sub.cancel();
    }
    _roomSubs.clear();
    for (final room in _voiceRooms) {
      final activities = room.getComponent<ActivitiesComponent>();
      if (activities != null) {
        _roomSubs.add(activities.onSessionsChanged.listen((_) => _update()));
      }
    }
    _update();
  }

  /// Calls in this space that you're in: their streams say who's sharing.
  void _watchCalls() {
    for (final sub in _callSubs) {
      sub.cancel();
    }
    _callSubs.clear();
    for (final call in _callsHere) {
      _callSubs.add(call.onStateChanged.listen((_) => _update()));
    }
    _update();
  }

  Iterable<VoipSession> get _callsHere {
    final ids = {for (final room in _voiceRooms) room.identifier};
    return clientManager!.callManager.currentSessions.where((call) =>
        call.client == widget.space.client &&
        ids.contains(call.roomId) &&
        call.state == VoipState.connected);
  }

  void _update() {
    if (!mounted) return;
    final enabled = preferences.experimentSidebarSubspaceGuides.value;
    final nowOccupied = enabled &&
        _voiceRooms.any((room) =>
            room
                .getComponent<ActivitiesComponent>()
                ?.getSessions()
                .any((s) => !s.thirdparty && s.participants.isNotEmpty) ??
            false);
    final nowLive = enabled &&
        _callsHere.any((call) =>
            call.streams.any((s) => s.type == VoipStreamType.screenshare));
    if (nowOccupied == occupied && nowLive == live) return;
    setState(() {
      occupied = nowOccupied;
      live = nowLive;
    });
  }

  @override
  void dispose() {
    for (final sub in [..._subs, ..._roomSubs, ..._callSubs]) {
      sub.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!occupied && !live) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    // Separates the mark from the space's picture, like a presence dot.
    final ring = scheme.surfaceContainerLowest;
    if (live) {
      return Semantics(
        label: "Someone is sharing their screen",
        child: Container(
          padding: const EdgeInsets.all(2.5),
          decoration: BoxDecoration(
              color: ring, borderRadius: BorderRadius.circular(8)),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
                color: _liveRed, borderRadius: BorderRadius.circular(5)),
            child: Text("LIVE",
                style: TextStyle(
                    fontSize: 9,
                    height: 1.2,
                    letterSpacing: 0.3,
                    fontWeight: FontWeight.w800,
                    color: Colors.white)),
          ),
        ),
      );
    }
    return Semantics(
      label: "People are in a call here",
      child: Container(
        width: 20,
        height: 20,
        padding: const EdgeInsets.all(2.5),
        decoration: BoxDecoration(color: ring, shape: BoxShape.circle),
        child: Container(
          decoration: BoxDecoration(
              color: VoiceRoomOccupancy.greenFor(context),
              shape: BoxShape.circle),
          child: const Icon(Icons.headphones, size: 10, color: Colors.white),
        ),
      ),
    );
  }
}
