import 'package:commet/ui/molecules/room_timeline_widget/room_timeline_overlay.dart';
import 'package:commet/ui/molecules/timeline_events/timeline_event_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

TimelineEventMenuEntry _entry(String name, IconData icon) =>
    TimelineEventMenuEntry(name: name, icon: icon);

void main() {
  final forward = _entry("Forward", Icons.shortcut);
  final reply = _entry("Reply", Icons.reply);
  final copy = _entry("Copy image", Icons.copy);
  final save = _entry("Save as", Icons.save_alt);

  test("hover bar: Forward goes right after Reply", () {
    expect(TimelineOverlayState.withHoverForward(forward, [reply, copy, save]),
        [reply, forward, copy, save]);
  });

  test("hover bar: Forward goes first without Reply", () {
    expect(TimelineOverlayState.withHoverForward(forward, [copy, save]),
        [forward, copy, save]);
  });

  test("hover bar: unchanged when the message has no Forward", () {
    final actions = [reply, copy];
    expect(TimelineOverlayState.withHoverForward(null, actions), [reply, copy]);
  });
}
