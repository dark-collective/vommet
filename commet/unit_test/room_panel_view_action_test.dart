import 'dart:async';

import 'package:commet/ui/atoms/room_panel_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Vommet issue 332: a join or accept the server refuses must free the button
// and show the server's error, not spin forever.
Future<void> _pumpPanel(WidgetTester tester,
    {Future<void> Function()? primary,
    Future<void> Function()? secondary}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: RoomPanelView(
        displayName: "Room",
        primaryButtonLabel: "Join",
        onPrimaryButtonPressed: primary,
        secondaryButtonLabel: secondary == null ? null : "Reject",
        onSecondaryButtonPressed: secondary,
      ),
    ),
  ));
}

void main() {
  testWidgets("a failed primary action shows its error and stops loading",
      (tester) async {
    final done = Completer<void>();
    await _pumpPanel(tester, primary: () => done.future);

    await tester.tap(find.text("Join"));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    done.completeError(Exception("M_FORBIDDEN: You are not allowed to join"));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining("M_FORBIDDEN: You are not allowed to join"),
        findsOneWidget);
  });

  testWidgets("a failed secondary action shows its error and stops loading",
      (tester) async {
    await _pumpPanel(tester,
        primary: () async {},
        secondary: () async => throw Exception("M_UNKNOWN: leave failed"));

    await tester.tap(find.text("Reject"));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining("M_UNKNOWN: leave failed"), findsOneWidget);
  });

  testWidgets("a successful action stops loading without a dialog",
      (tester) async {
    var calls = 0;
    await _pumpPanel(tester, primary: () async => calls++);

    await tester.tap(find.text("Join"));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(calls, 1);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining("Error"), findsNothing);
    expect(find.text("Join"), findsOneWidget);
  });
}
