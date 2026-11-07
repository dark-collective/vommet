import 'dart:async';

import 'package:commet/client/timeline_events/timeline_event.dart';
import 'package:commet/ui/organisms/chat/prefixed_sends.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Vommet issue 565: "Sending as <account>…" for messages sent from another
// account with an account-switch prefix, until they reach the viewed timeline.

class _Event extends Fake implements TimelineEvent {
  _Event(this.eventId);

  @override
  final String eventId;
}

void main() {
  late Set<String> timeline;
  late PrefixedSends sends;

  setUp(() {
    timeline = {};
    sends = PrefixedSends(timeline.contains,
        pollInterval: const Duration(milliseconds: 10));
  });

  tearDown(() => sends.dispose());

  Future<void> settle() => Future.delayed(const Duration(milliseconds: 30));

  test("pending until the event reaches the viewed timeline", () async {
    final sending = Completer<TimelineEvent?>();
    sends.track("@me:other.example", sending.future, retry: () async => null);
    expect(sends.pending, hasLength(1));

    sending.complete(_Event("\$a"));
    await settle();
    expect(sends.pending, hasLength(1), reason: "sent, not arrived yet");

    timeline.add("\$a");
    await settle();
    expect(sends.sends, isEmpty);
  });

  test("an edit is done once it is sent", () async {
    sends.track("@me:other.example", Future.value(_Event("\$edit")),
        retry: () async => null, awaitArrival: false);
    await settle();
    expect(sends.sends, isEmpty);
  });

  test("a failed send can be retried or dismissed", () async {
    sends.track("@me:other.example", Future.error(Exception("offline")),
        retry: () async => _Event("\$b"));
    sends.track("@me:other.example", Future.value(null),
        retry: () async => null);
    await settle();
    expect(sends.failed, hasLength(2));
    expect(sends.pending, isEmpty);

    sends.retry(sends.failed.first);
    await settle();
    expect(sends.failed, hasLength(1));
    expect(sends.pending, hasLength(1));

    sends.dismiss(sends.failed.first);
    timeline.add("\$b");
    await settle();
    expect(sends.sends, isEmpty);
  });

  test("gives up on an event that never arrives", () async {
    sends.dispose();
    sends = PrefixedSends(timeline.contains,
        pollInterval: const Duration(milliseconds: 10),
        giveUpAfter: const Duration(milliseconds: 20));
    sends.track("@me:other.example", Future.value(_Event("\$c")),
        retry: () async => null);
    await Future.delayed(const Duration(milliseconds: 80));
    expect(sends.sends, isEmpty);
  });

  testWidgets("shows a count and the failure", (tester) async {
    final first = Completer<TimelineEvent?>();
    final second = Completer<TimelineEvent?>();
    final failing = Completer<TimelineEvent?>();
    sends.track("@me:other.example", first.future, retry: () async => null);
    sends.track("@me:other.example", second.future, retry: () async => null);
    sends.track("@me:other.example", failing.future, retry: () async => null);

    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: PrefixedSendStatus(sends))));
    expect(
        find.text("Sending 3 messages as @me:other.example…"), findsOneWidget);

    failing.complete(null);
    await tester.pump();
    expect(find.text("Couldn't send as @me:other.example"), findsOneWidget);
    expect(
        find.text("Sending 2 messages as @me:other.example…"), findsOneWidget);

    await tester.tap(find.text("Dismiss"));
    await tester.pump();
    expect(find.textContaining("Couldn't send"), findsNothing);

    first.complete(_Event("\$d"));
    second.complete(_Event("\$e"));
    await tester.pump();
    expect(
        find.text("Sending 2 messages as @me:other.example…"), findsOneWidget);

    timeline.addAll(["\$d", "\$e"]);
    await tester.pump(const Duration(milliseconds: 20));
    expect(find.textContaining("Sending"), findsNothing);
  });
}
