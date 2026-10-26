import 'package:commet/client/client.dart';
import 'package:commet/client/components/component.dart';

/// Vommet: the spaces and rooms you share with another user, for their
/// profile card.
class MutualRooms {
  const MutualRooms(
      {this.spaces = const [],
      this.rooms = const [],
      this.memberCounts = const {}});

  final List<Space> spaces;
  final List<Room> rooms;

  /// Joined member count per space or room id, where known.
  final Map<String, int> memberCounts;

  bool get isEmpty => spaces.isEmpty && rooms.isEmpty;
}

abstract class MutualRoomsComponent<T extends Client> implements Component<T> {
  /// Spaces and rooms both you and [userId] have joined. Your direct message
  /// with them is left out.
  Future<MutualRooms> getMutualRooms(String userId);
}
