// Vommet issue 719: Mark all as read marks every unread room, a few at a
// time, and keeps going past a room that fails.
import 'dart:async';

import 'package:commet/client/room.dart';
import 'package:commet/utils/mark_all_read.dart';
import 'package:flutter_test/flutter_test.dart';

class _Room extends Fake implements Room {
  _Room(this.name,
      {this.notificationCount = 0,
      this.highlightedNotificationCount = 0,
      this.pushRule = PushRule.notify,
      this.fails = false});

  final String name;
  final bool fails;

  @override
  final int notificationCount;

  @override
  final int highlightedNotificationCount;

  @override
  final PushRule pushRule;

  static int running = 0;
  static int mostAtOnce = 0;
  static final List<String> marked = [];

  @override
  Future<void> markAsRead() async {
    running++;
    if (running > mostAtOnce) mostAtOnce = running;
    await Future.delayed(const Duration(milliseconds: 5));
    running--;
    if (fails) throw StateError("offline");
    marked.add(name);
  }
}

void main() {
  setUp(() {
    _Room.running = 0;
    _Room.mostAtOnce = 0;
    _Room.marked.clear();
  });

  test("a room with a count or a mention is unread", () {
    expect(MarkAllRead.isUnread(_Room("a", notificationCount: 2)), isTrue);
    expect(MarkAllRead.isUnread(_Room("b", highlightedNotificationCount: 1)),
        isTrue);
    expect(MarkAllRead.isUnread(_Room("c")), isFalse);
  });

  test("a muted room with a count is marked too", () {
    expect(
        MarkAllRead.isUnread(_Room("muted",
            notificationCount: 3, pushRule: PushRule.dontNotify)),
        isTrue);
  });

  test("marks every room, a few at a time", () async {
    final rooms = [
      for (var i = 0; i < 10; i++) _Room("r$i", notificationCount: 1)
    ];
    await MarkAllRead.mark(rooms);
    expect(_Room.marked.toSet(), {for (var i = 0; i < 10; i++) "r$i"});
    expect(_Room.mostAtOnce, lessThanOrEqualTo(MarkAllRead.batch));
  });

  test("a room that fails doesn't stop the others", () async {
    await MarkAllRead.mark([
      _Room("a", notificationCount: 1),
      _Room("b", notificationCount: 1, fails: true),
      _Room("c", notificationCount: 1),
    ]);
    expect(_Room.marked, unorderedEquals(["a", "c"]));
  });
}
