import 'package:commet/client/client.dart';
import 'package:commet/client/room_preview.dart';

abstract class SpaceChild<T> {
  String get id;
  final T child;

  SpaceChild(this.child);
}

class SpaceChildRoom<T extends Room> implements SpaceChild<T> {
  @override
  final T child;

  @override
  String get id => child.identifier;

  SpaceChildRoom(this.child);
}

class SpaceChildSpace<T extends Space> implements SpaceChild<T> {
  @override
  final T child;

  @override
  String get id => child.identifier;

  SpaceChildSpace(this.child);
}

/// Vommet: a child the account isn't in (never joined, or left). Only its id
/// is known for sure; [child] is its preview from the space's hierarchy,
/// once that has loaded. Space editors can still reorder or remove it.
class SpaceChildUnjoined implements SpaceChild<RoomPreview?> {
  @override
  final String id;

  @override
  final RoomPreview? child;

  SpaceChildUnjoined(this.id, this.child);
}
