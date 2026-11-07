// Vommet: Matrix side of the space join picker: `/hierarchy` pages, joins,
// and which errors mean "slow down".

import 'package:commet/utils/space_hierarchy/space_tree.dart';
import 'package:matrix/matrix.dart' as matrix;

class MatrixSpaceHierarchy {
  static HierarchyFetcher fetcher(matrix.Client mx) =>
      (String spaceId, {String? from, required int limit}) async {
        final response = await mx.getSpaceHierarchy(spaceId,
            from: from, limit: limit, maxDepth: 1);
        return HierarchyPage(response.rooms.map(convert).toList(),
            nextBatch: response.nextBatch);
      };

  static HierarchyRoomInfo convert(matrix.SpaceRoomsChunk$2 chunk) {
    final links = <HierarchyChildLink>[];
    for (final state in chunk.childrenState) {
      final childId = state.stateKey;
      if (state.type != matrix.EventTypes.SpaceChild || childId == null) {
        continue;
      }
      final via = state.content["via"];
      // A child link without servers is a removed one.
      if (via is! List || via.isEmpty) continue;
      links.add(HierarchyChildLink(childId,
          suggested: state.content["suggested"] == true,
          via: via.whereType<String>().toList()));
    }
    return HierarchyRoomInfo(
      roomId: chunk.roomId,
      name: chunk.name ?? chunk.canonicalAlias,
      avatarUrl: chunk.avatarUrl,
      roomType: chunk.roomType,
      members: chunk.numJoinedMembers,
      joinRule: chunk.joinRule,
      topic: chunk.topic,
      children: links,
    );
  }

  static bool isJoined(matrix.Client mx, String roomId) =>
      mx.getRoomById(roomId)?.membership == matrix.Membership.join;

  /// How long to wait before retrying, for a rate-limit error.
  static Duration? retryAfter(Object error) {
    if (error is matrix.MatrixException &&
        error.error == matrix.MatrixError.M_LIMIT_EXCEEDED) {
      return Duration(milliseconds: error.retryAfterMs ?? 0);
    }
    return null;
  }

  /// A short reason for the failure line on the progress card.
  static String failureReason(Object error, {String? joinRule}) {
    if (error is matrix.MatrixException) {
      if (error.error == matrix.MatrixError.M_FORBIDDEN) {
        return joinRule == "invite" ||
                joinRule == "knock" ||
                joinRule == "restricted" ||
                joinRule == "knock_restricted"
            ? "invite only"
            : "not allowed";
      }
      if (error.error == matrix.MatrixError.M_LIMIT_EXCEEDED) {
        return "server busy";
      }
      if (error.error == matrix.MatrixError.M_NOT_FOUND) return "not found";
    }
    return "error";
  }
}
