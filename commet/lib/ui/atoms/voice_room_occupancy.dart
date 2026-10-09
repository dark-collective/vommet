import 'package:commet/client/components/activities/activities_component.dart';
import 'package:commet/client/room.dart';
import 'package:commet/main.dart';
import 'package:flutter/material.dart';

/// Vommet: who is in a voice room's call, for the sidebar (experiment
/// `experiment_sidebar_subspace_guides`). Only says who has joined, never who
/// is talking: we can't know that without being in the call.
class VoiceRoomOccupancy {
  VoiceRoomOccupancy._(this.participants, this.includesYou);

  static const Color green = Color(0xff23a55a);

  final Set<String> participants;
  final bool includesYou;

  bool get occupied => participants.isNotEmpty;

  /// Null when the experiment is off.
  static VoiceRoomOccupancy? of(
      Room room, List<RoomActivitySession>? sessions) {
    if (!preferences.experimentSidebarSubspaceGuides.value) return null;
    final people = <String>{
      for (final session in sessions ?? const <RoomActivitySession>[])
        if (!session.thirdparty) ...session.participants,
    };
    final self = room.client.self?.identifier;
    return VoiceRoomOccupancy._(people, self != null && people.contains(self));
  }

  /// Green "person N" pill for the end of the room's row.
  Widget buildCount() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      margin: const EdgeInsets.only(right: 2),
      decoration: BoxDecoration(
          color: green.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(10)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.person, size: 12, color: green),
        const SizedBox(width: 2),
        Text("${participants.length}",
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: green,
                height: 1)),
      ]),
    );
  }
}
