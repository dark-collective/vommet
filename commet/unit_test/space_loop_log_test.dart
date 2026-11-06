import 'package:commet/client/client.dart';
import 'package:commet/client/room.dart';
import 'package:commet/client/space.dart';
import 'package:commet/debug/log.dart';
import 'package:flutter_test/flutter_test.dart';

class _Room extends Fake implements Room {
  _Room(this.identifier);

  @override
  final String identifier;
}

class _Client extends Fake implements Client {}

final _client = _Client();

class _Space extends Space {
  _Space(this.identifier, this.rooms);

  @override
  final String identifier;
  @override
  final List<Room> rooms;
  @override
  List<Space> subspaces = [];
  @override
  Client get client => _client;
  @override
  String get displayName => "Space $identifier";

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

int loopWarnings() => Log.log
    .where((e) => e.rawContent.contains("Detected recursive space hierarchy"))
    .fold(0, (sum, e) => sum + e.count);

List<String> ids(List<Room> rooms) => rooms.map((r) => r.identifier).toList();

void main() {
  setUp(() => Log.log.clear());

  test("a 3-space loop is logged once as a warning, each room once", () {
    final a = _Space("!a", [_Room("a1")]);
    final b = _Space("!b", [_Room("b1")]);
    final c = _Space("!c", [_Room("c1"), _Room("c2")]);
    a.subspaces = [b];
    b.subspaces = [c];
    c.subspaces = [a];

    for (var i = 0; i < 50; i++) {
      for (final s in [a, b, c]) {
        final rooms = ids(s.roomsWithChildren);
        expect(rooms.toSet().length, rooms.length, reason: "duplicates");
        expect(rooms.toSet(), {"a1", "b1", "c1", "c2"});
      }
      // A log line in between, as in the real log, so repeats can't merge.
      Log.i("Received filter change event!");
    }

    expect(loopWarnings(), 1);
    final entry = Log.log.firstWhere(
        (e) => e.rawContent.contains("Detected recursive space hierarchy"));
    expect(entry.type, LogType.warning);
    expect(entry.rawContent, contains("Space !a"));
    expect(ids(a.roomsWithChildren), ["a1", "b1", "c1", "c2"]);
  });

  test("a diamond is not a loop and its shared space's rooms appear once", () {
    final a = _Space("!a2", [_Room("a1")]);
    final b = _Space("!b2", [_Room("b1")]);
    final c = _Space("!c2", [_Room("c1")]);
    final d = _Space("!d2", [_Room("d1"), _Room("d2")]);
    a.subspaces = [b, c];
    b.subspaces = [d];
    c.subspaces = [d];

    expect(ids(a.roomsWithChildren), ["a1", "b1", "d1", "d2", "c1"]);
    expect(loopWarnings(), 0);
  });

  test("a plain tree keeps the same rooms in the same order", () {
    final a = _Space("!a3", [_Room("a1"), _Room("a2")]);
    final b = _Space("!b3", [_Room("b1")]);
    final c = _Space("!c3", [_Room("c1")]);
    final d = _Space("!d3", [_Room("d1")]);
    final e = _Space("!e3", [_Room("e1")]);
    a.subspaces = [b, e];
    b.subspaces = [c, d];

    expect(ids(a.roomsWithChildren), ["a1", "a2", "b1", "c1", "d1", "e1"]);
    expect(loopWarnings(), 0);
  });

  test("a loop below the root (A -> B -> C -> B) is logged once", () {
    final a = _Space("!a4", [_Room("a1")]);
    final b = _Space("!b4", [_Room("b1")]);
    final c = _Space("!c4", [_Room("c1")]);
    a.subspaces = [b];
    b.subspaces = [c];
    c.subspaces = [b];

    for (var i = 0; i < 20; i++) {
      expect(ids(a.roomsWithChildren), ["a1", "b1", "c1"]);
      Log.i("Received filter change event!");
    }
    expect(loopWarnings(), 1);
    final entry = Log.log.firstWhere(
        (e) => e.rawContent.contains("Detected recursive space hierarchy"));
    // Only the spaces in the loop are named, not the root above it.
    expect(entry.rawContent, isNot(contains("Space !a4")));
  });

  test("two different loops are each logged once", () {
    final a = _Space("!a5", [_Room("a1")]);
    final b = _Space("!b5", [_Room("b1")]);
    final c = _Space("!c5", [_Room("c1")]);
    final d = _Space("!d5", [_Room("d1")]);
    a.subspaces = [b, c];
    b.subspaces = [a];
    c.subspaces = [d];
    d.subspaces = [c];

    for (var i = 0; i < 20; i++) {
      expect(ids(a.roomsWithChildren).toSet(), {"a1", "b1", "c1", "d1"});
      Log.i("Received filter change event!");
    }
    expect(loopWarnings(), 2);
  });

  test("the same loop reached from another root is not logged again", () {
    final a = _Space("!a6", [_Room("a1")]);
    final b = _Space("!b6", [_Room("b1")]);
    final top = _Space("!top6", [_Room("t1")]);
    a.subspaces = [b];
    b.subspaces = [a];
    top.subspaces = [a];

    for (var i = 0; i < 20; i++) {
      a.roomsWithChildren;
      b.roomsWithChildren;
      top.roomsWithChildren;
      Log.i("Received filter change event!");
    }
    expect(loopWarnings(), 1);
  });
}
