// Vommet issue 549: Alt+Up/Down and Alt+Shift+Up/Down in the unified chat
// list follow the rows shown, going through a space row's rooms. Made-up
// names.
import 'package:commet/ui/organisms/unified_chat_list/unified_chat_model.dart';
import 'package:flutter_test/flutter_test.dart';

ChatEntry chat(String id, {int unread = 0}) =>
    ChatEntry(key: "acct:$id", roomId: id, name: id, unread: unread);

SpaceTopRow spaceRow(String id, List<ChatEntry> rooms) => SpaceTopRow(
    SpaceEntry(key: "acct:$id", spaceId: id, name: id, rooms: rooms));

void main() {
  final otter = chat("otter");
  final general = chat("general");
  final music = chat("music", unread: 2);
  final heron = chat("heron", unread: 1);
  final rows = <TopRow>[
    ChatTopRow(otter),
    spaceRow("pond", [general, music]),
    ChatTopRow(heron),
  ];
  final stops = chatListStops(rows);

  String? next(String? current, String? open,
      {bool forward = true, bool unreadOnly = false}) {
    final stop = stepChatList(stops, current, open,
        forward: forward, where: unreadOnly ? (c) => c.unread > 0 : null);
    return stop == null ? null : "${stop.chat.roomId}@${stop.spaceKey}";
  }

  test("a space row stands for its rooms, in the pane's order", () {
    expect(stops.map((s) => (s.chat.roomId, s.spaceKey)), [
      ("otter", null),
      ("general", "acct:pond"),
      ("music", "acct:pond"),
      ("heron", null),
    ]);
  });

  test("down into a space, through its rooms, and back out", () {
    expect(next("acct:otter", null), "general@acct:pond");
    expect(next("acct:general", "acct:pond"), "music@acct:pond");
    expect(next("acct:music", "acct:pond"), "heron@null");
  });

  test("up from a space's first room selects the chat above the space", () {
    expect(next("acct:general", "acct:pond", forward: false), "otter@null");
    expect(next("acct:heron", null, forward: false), "music@acct:pond");
  });

  test("nothing past either end", () {
    expect(next("acct:otter", null, forward: false), isNull);
    expect(next("acct:heron", null), isNull);
  });

  test("Shift stops only on unread chats", () {
    expect(next("acct:otter", null, unreadOnly: true), "music@acct:pond");
    expect(next("acct:music", "acct:pond", unreadOnly: true), "heron@null");
    expect(next("acct:heron", null, forward: false, unreadOnly: true),
        "music@acct:pond");
  });

  test("a chat not in the list starts from the first or last stop", () {
    expect(next(null, null), "otter@null");
    expect(next("acct:elsewhere", null, forward: false), "heron@null");
  });

  test("a room in two spaces is found in the open one", () {
    final shared = chat("shared");
    final twice = chatListStops([
      spaceRow("a", [shared]),
      ChatTopRow(otter),
      spaceRow("b", [shared]),
    ]);
    final stop = stepChatList(twice, "acct:shared", "acct:b", forward: false);
    expect(stop?.chat.roomId, "otter");
  });

  test("openTop opens the space itself, not its last subspace", () {
    final nav = SpaceNavigation()
      ..openRoot("acct:pond")
      ..drillInto("acct:reeds")
      ..close();
    nav.openTop("acct:pond");
    expect(nav.path, ["acct:pond"]);
  });
}
