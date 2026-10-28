import 'package:commet/client/client.dart';
import 'package:commet/ui/pages/get_or_create_room/room_creator.dart';
import 'package:test/test.dart';

void main() {
  test("accepts Matrix user IDs only", () {
    expect(RoomFieldCoOwners.isUserId("@maple:example.org"), isTrue);
    expect(RoomFieldCoOwners.isUserId("@fern:otherhost.net:8448"), isTrue);
    expect(RoomFieldCoOwners.isUserId("maple:example.org"), isFalse);
    expect(RoomFieldCoOwners.isUserId("@maple"), isFalse);
    expect(RoomFieldCoOwners.isUserId("@ma ple:example.org"), isFalse);
    expect(RoomFieldCoOwners.isUserId(""), isFalse);
  });

  test("adds trimmed co-owners once", () {
    final args = CreateRoomArgs();
    expect(args.additionalCreators, isEmpty);
    expect(
        RoomFieldCoOwners.addCoOwner(
            args.additionalCreators, " @maple:example.org "),
        isTrue);
    expect(
        RoomFieldCoOwners.addCoOwner(
            args.additionalCreators, "@maple:example.org"),
        isFalse);
    expect(RoomFieldCoOwners.addCoOwner(args.additionalCreators, "not an id"),
        isFalse);
    expect(args.additionalCreators, ["@maple:example.org"]);
  });
}
