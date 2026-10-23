import 'package:commet/client/client.dart' as c;

/// Vommet: maps a room's Matrix type (`m.room.create`'s `type`, as given in
/// a room summary or a space hierarchy chunk) to Commet's [c.RoomType]. One
/// mapping for every room preview: the space hierarchy used to know only
/// spaces, so voice rooms you hadn't joined showed as text rooms.
c.RoomType matrixRoomType(String? type) => switch (type) {
      "m.space" => c.RoomType.space,
      "chat.commet.calendar" => c.RoomType.calendar,
      "chat.commet.photo_album" => c.RoomType.photoAlbum,
      "org.matrix.msc3417.call" => c.RoomType.voipRoom,
      _ => c.RoomType.defaultRoom,
    };
