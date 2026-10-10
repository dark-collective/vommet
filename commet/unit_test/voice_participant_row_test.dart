import 'dart:async';

import 'package:commet/client/components/voip/voip_participants.dart';
import 'package:commet/client/member.dart';
import 'package:commet/ui/atoms/voice_participant_row.dart';
import 'package:commet/ui/atoms/voice_room_occupancy.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Member implements Member {
  _Member(this.identifier, this.displayName);
  @override
  final String identifier;
  @override
  final String displayName;
  @override
  ImageProvider? get avatar => null;
  @override
  Color get defaultColor => Colors.teal;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Call implements VoipParticipants {
  // Synchronous, so a change is applied before the next frame is pumped.
  final changes = StreamController<void>.broadcast(sync: true);
  @override
  Set<String> speakingUserIds = {};
  @override
  Set<String> micOffUserIds = {};
  @override
  Stream<void> get onParticipantsChanged => changes.stream;
  void set({Set<String>? speaking, Set<String>? micOff}) {
    if (speaking != null) speakingUserIds = speaking;
    if (micOff != null) micOffUserIds = micOff;
    changes.add(null);
  }
}

const juniper = "@juniper:example.org";

Widget _app(Widget child) => MaterialApp(home: Material(child: child));

bool _ringOn(WidgetTester tester) {
  final box = tester.widget<Container>(find
      .descendant(
          of: find.byType(VoiceParticipantRow),
          matching: find.byWidgetPredicate((w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).border != null))
      .first);
  final border = (box.decoration as BoxDecoration).border as Border;
  return border.top.color ==
      VoiceRoomOccupancy.greenFor(
          tester.element(find.byType(VoiceParticipantRow)));
}

void main() {
  testWidgets("lights up while talking, held briefly after", (tester) async {
    final call = _Call();
    await tester.pumpWidget(
        _app(VoiceParticipantRow(_Member(juniper, "Juniper"), call: call)));
    expect(_ringOn(tester), false);

    call.set(speaking: {juniper});
    await tester.pump();
    expect(_ringOn(tester), true);
    expect(tester.widget<Text>(find.text("Juniper")).style?.fontWeight,
        FontWeight.w600);

    // Stopped: still lit within the hold, off after it.
    call.set(speaking: {});
    await tester.pump(const Duration(milliseconds: 200));
    expect(_ringOn(tester), true);
    // Starts again within the hold: no blink.
    call.set(speaking: {juniper});
    await tester.pump(const Duration(milliseconds: 300));
    expect(_ringOn(tester), true);
    call.set(speaking: {});
    await tester
        .pump(VoiceParticipantRow.hold + const Duration(milliseconds: 50));
    expect(_ringOn(tester), false);
  });

  testWidgets("a muted person never lights up and shows the mark",
      (tester) async {
    final call = _Call();
    await tester.pumpWidget(
        _app(VoiceParticipantRow(_Member(juniper, "Juniper"), call: call)));
    call.set(speaking: {juniper}, micOff: {juniper});
    await tester.pump();
    expect(_ringOn(tester), false);
    expect(find.byIcon(Icons.mic_off), findsOneWidget);
    call.set(micOff: {});
    await tester.pump();
    expect(find.byIcon(Icons.mic_off), findsNothing);
    expect(_ringOn(tester), true);
  });

  testWidgets("a call you're not in shows only who's there", (tester) async {
    await tester.pumpWidget(
        _app(VoiceParticipantRow(_Member(juniper, "Juniper"), isYou: true)));
    expect(_ringOn(tester), false);
    expect(find.byIcon(Icons.mic_off), findsNothing);
    expect(find.text("Juniper (you)"), findsOneWidget);
  });
}
