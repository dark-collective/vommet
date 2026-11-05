import 'package:commet/client/room_preview.dart';
import 'package:commet/client/space.dart';
import 'package:commet/client/space_child.dart';
import 'package:commet/utils/personal_child_order.dart';

export 'package:commet/utils/personal_child_order.dart';

/// Private, account-scoped sibling order. Shared editors keep using children /
/// allChildren, which always reflect the space default.
abstract interface class PersonalSpaceOrdering {
  static const type = 'im.nether.chat.space_child_order';

  static PersonalSpaceOrdering? of(Space space) =>
      space is PersonalSpaceOrdering ? space as PersonalSpaceOrdering : null;

  String get personalOrderAccountId;
  List<String>? get personalChildOrder;
  Future<void> savePersonalChildOrder(List<String>? order);
}

extension PersonalSpaceChildren on Space {
  List<SpaceChild> get childrenForMe => PersonalChildOrder.project(children,
      PersonalSpaceOrdering.of(this)?.personalChildOrder, (c) => c.id);

  List<SpaceChild> get allChildrenForMe => PersonalChildOrder.project(
      allChildren,
      PersonalSpaceOrdering.of(this)?.personalChildOrder,
      (c) => c.id);

  /// Keep previews in their existing section; order within it by the same
  /// complete sibling projection, rather than the hierarchy response order.
  List<RoomPreview> get childPreviewsForMe {
    final rank = {for (final c in allChildrenForMe) c.id: c};
    final byId = {for (final preview in childPreviews) preview.roomId: preview};
    return [
      for (final id in rank.keys)
        if (byId.remove(id) case final preview?) preview,
      ...byId.values,
    ];
  }
}
