import 'package:commet/client/client.dart';
import 'package:commet/client/matrix/matrix_room_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('maps Matrix room types', () {
    expect(matrixRoomType("m.space"), RoomType.space);
    expect(matrixRoomType("org.matrix.msc3417.call"), RoomType.voipRoom);
    expect(matrixRoomType("chat.commet.calendar"), RoomType.calendar);
    expect(matrixRoomType("chat.commet.photo_album"), RoomType.photoAlbum);
  });

  test('untyped and unknown rooms are text rooms', () {
    expect(matrixRoomType(null), RoomType.defaultRoom);
    expect(matrixRoomType("org.example.unknown"), RoomType.defaultRoom);
  });
}
