import 'package:commet/utils/room_search.dart';
import 'package:test/test.dart';

class _R {
  final String name;
  final String id;
  final DateTime? last;
  _R(this.name, this.id, [this.last]);
  @override
  String toString() => name;
}

List<String> _rank(List<_R> rooms, String q) => RoomSearch.rank(rooms, q,
    name: (r) => r.name,
    id: (r) => r.id,
    lastActive: (r) => r.last).map((r) => r.name).toList();

void main() {
  final rooms = [
    _R("Off Topic", "!aaa:nether.im", DateTime(2026, 1, 1)),
    _R("Light Voice", "!bbb:nether.im", DateTime(2026, 3, 1)),
    _R("Voice Bridge Discussion", "!ccc:nether.im", DateTime(2026, 2, 1)),
    _R("Purple Gaming", "!ddd:nether.im"),
    _R("Announcements", "!voiceid:nether.im", DateTime(2026, 4, 1)),
  ];

  test("empty query keeps the original order", () {
    expect(_rank(rooms, "  "), rooms.map((r) => r.name).toList());
  });

  test("name prefix beats word prefix beats id match", () {
    expect(_rank(rooms, "voice"),
        ["Voice Bridge Discussion", "Light Voice", "Announcements"]);
  });

  test("matching is case-insensitive", () {
    expect(_rank(rooms, "PURPLE"), ["Purple Gaming"]);
  });

  test("substring inside a word matches after prefixes", () {
    expect(_rank(rooms, "ming"), ["Purple Gaming"]);
  });

  test("ties are broken by most recent activity", () {
    final tied = [
      _R("General", "!1:x", DateTime(2026, 1, 1)),
      _R("General", "!2:x", DateTime(2026, 5, 1)),
      _R("General", "!3:x"),
    ];
    expect(
        RoomSearch.rank(tied, "gen",
            name: (r) => r.name,
            id: (r) => r.id,
            lastActive: (r) => r.last).map((r) => r.id).toList(),
        ["!2:x", "!1:x", "!3:x"]);
  });

  test("no match returns nothing", () {
    expect(_rank(rooms, "zzz"), isEmpty);
  });
}
