import 'package:commet/utils/space_paths.dart';
import 'package:test/test.dart';

class FakeSpace {
  FakeSpace(this.id, {this.rooms = const [], List<FakeSpace>? subspaces})
      : subspaces = subspaces ?? [];

  final String id;
  final List<String> rooms;
  final List<FakeSpace> subspaces;
}

Map<String, List<List<FakeSpace>>> index(List<FakeSpace> top) =>
    SpacePaths.index<FakeSpace>(top,
        roomIds: (s) => s.rooms,
        subspaces: (s) => s.subspaces,
        id: (s) => s.id);

String? label(Map<String, List<List<FakeSpace>>> paths, String room,
        {List<FakeSpace> inside = const []}) =>
    SpacePaths.label<FakeSpace>(paths[room],
        name: (s) => s.id, id: (s) => s.id, inside: inside);

void main() {
  // Two spaces each with a "general" room, one of them nested.
  final gamesSub = FakeSpace("Minecraft", rooms: ["general-mc"]);
  final games =
      FakeSpace("Games", rooms: ["general-games"], subspaces: [gamesSub]);
  final work = FakeSpace("Work", rooms: ["general-work", "shared"]);
  final friends = FakeSpace("Friends", rooms: ["shared"]);

  final paths = index([games, work, friends]);

  test("rooms in a top-level space", () {
    expect(label(paths, "general-games"), "Games");
    expect(label(paths, "general-work"), "Work");
  });

  test("rooms in a subspace show the whole chain", () {
    expect(label(paths, "general-mc"), "Games › Minecraft");
  });

  test("a room in several spaces shows the first and a count", () {
    expect(label(paths, "shared"), "Work +1");
  });

  test("rooms in no space have no label", () {
    expect(label(paths, "dm-with-alice"), isNull);
  });

  test("inside a space, its own part of the chain is left out", () {
    expect(label(paths, "general-games", inside: [games]), isNull);
    expect(label(paths, "general-mc", inside: [games]), "Minecraft");
    expect(label(paths, "general-mc", inside: [games, gamesSub]), isNull);
  });

  test("inside a space, chains through other spaces are ignored", () {
    expect(label(paths, "shared", inside: [friends]), isNull);
    expect(label(paths, "general-mc", inside: [work]), isNull);
  });

  test("shortest chain comes first", () {
    final deep = FakeSpace("Deep", rooms: ["r"]);
    final mid = FakeSpace("Mid", subspaces: [deep]);
    final top = FakeSpace("Top", rooms: ["r"], subspaces: [mid]);
    final p = index([top]);
    expect(p["r"]!.map((c) => c.length), [1, 3]);
    expect(label(p, "r"), "Top +1");
  });

  test("a space that contains itself doesn't loop", () {
    final a = FakeSpace("A", rooms: ["r"]);
    final b = FakeSpace("B", subspaces: [a]);
    a.subspaces.add(b);
    final p = index([a]);
    expect(p["r"]!.length, 1);
  });
}
