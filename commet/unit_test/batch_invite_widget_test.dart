import 'dart:async';
import 'package:commet/config/layout_style.dart';
import 'package:commet/main.dart' show preferences, backgroundTaskManager;
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/ui/organisms/invitation_view/batch_invite_widget.dart';
import 'package:commet/ui/organisms/invitation_view/batch_invite_source.dart';
import 'package:commet/ui/organisms/invitation_view/invitation_batch_view.dart';
import 'package:commet/utils/space_hierarchy/invite_plan.dart';
import 'package:commet/utils/invitations/invitation_batch.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_dark.dart';
import 'invitation_batch_fixture.dart';

class ManyDestinations extends FakeBatchInviteSource {
  @override
  Future<List<InvitePlace>> loadPlaces() async => [
        InvitePlace(rootId, rootName, isSpace: true),
        for (var i = 0; i < 101; i++)
          InvitePlace('!r$i', 'Room $i', ancestors: [rootId])
      ];
}

class ExistingMembers extends FakeBatchInviteSource {
  @override
  InviteAccess access(String userId, String roomId) => InviteAccess(
      membership: 'join',
      history: roomId == rootId ? InviteHistory.space : InviteHistory.included,
      canInvite: true,
      canGrant: roomId == '!general');
}

class UnencryptedRoom extends FakeBatchInviteSource {
  UnencryptedRoom() : super(isSpace: false);
  @override
  InviteAccess access(String userId, String roomId) =>
      const InviteAccess(history: InviteHistory.notEncrypted, canInvite: true);
}

/// Sam can't be invited to Game night; the others can.
class PerPersonRooms extends FakeBatchInviteSource {
  @override
  InviteAccess access(String userId, String roomId) {
    final a = super.access(userId, roomId);
    return roomId == '!game' && userId == people[1].id
        ? InviteAccess(
            membership: a.membership, history: a.history, canInvite: false)
        : a;
  }
}

/// No invite power in the space itself, only in its rooms.
class NoSpacePower extends FakeBatchInviteSource {
  @override
  InviteAccess access(String userId, String roomId) {
    final a = super.access(userId, roomId);
    return roomId == rootId
        ? InviteAccess(
            membership: a.membership, history: a.history, canInvite: false)
        : a;
  }
}

void main() {
  setUpAll(() async {
    // unit_test is the repository’s test directory.
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
  });
  tearDown(() {
    for (final t in backgroundTaskManager.tasks.toList()) {
      t.dispose();
    }
    backgroundTaskManager.tasks.clear();
  });
  Future<void> open(
    WidgetTester tester,
    FakeBatchInviteSource source, {
    double scale = 1,
  }) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeDark.theme,
        builder: (c, w) => MediaQuery(
          data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
          child: w!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (c) => TextButton(
              onPressed: () => AdaptiveDialog.show(
                c,
                builder: (_) => BatchInviteWidget(source: source),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  Future<void> selectAll(
    WidgetTester tester,
    FakeBatchInviteSource source,
  ) async {
    for (final p in source.people) {
      await tester.ensureVisible(find.byKey(ValueKey('invite-person-${p.id}')));
      await tester.tap(find.byKey(ValueKey('invite-person-${p.id}')));
      await tester.pumpAndSettle();
    }
    await tester.pumpAndSettle();
  }

  testWidgets('selection persists across queries and duplicate results', (
    tester,
  ) async {
    final s = FakeBatchInviteSource();
    await open(tester, s);
    await tester.tap(find.byKey(ValueKey('invite-person-${s.people[0].id}')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Sam');
    await tester.pump(const Duration(milliseconds: 501));
    await tester.pumpAndSettle();
    expect(find.text('1 selected'), findsOneWidget);
    await tester.tap(find.byKey(ValueKey('invite-person-${s.people[1].id}')));
    await tester.pumpAndSettle();
    expect(find.text('2 selected'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();
    expect(find.text('2 selected'), findsOneWidget);
    await tester.tap(find.byTooltip('Remove Alex Rivera'));
    await tester.pumpAndSettle();
    expect(find.text('1 selected'), findsOneWidget);
  });
  testWidgets(
    'late search results cannot replace a newer query, failures retain picks',
    (tester) async {
      final s = FakeBatchInviteSource();
      final old = Completer<List<InvitePerson>>();
      s.searcher = (q) => q == 'old' ? old.future : Future.value([s.people[1]]);
      await open(tester, s);
      await tester.tap(find.byKey(ValueKey('invite-person-${s.people[0].id}')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'old');
      await tester.pump(const Duration(milliseconds: 501));
      await tester.enterText(find.byType(TextField), 'new');
      await tester.pump(const Duration(milliseconds: 501));
      await tester.pumpAndSettle();
      old.complete([s.people[2]]);
      await tester.pumpAndSettle();
      expect(
        find.byKey(ValueKey('invite-person-${s.people[1].id}')),
        findsOneWidget,
      );
      expect(
        find.byKey(ValueKey('invite-person-${s.people[2].id}')),
        findsNothing,
      );
      s.searcher = (_) async => throw StateError('offline');
      await tester.enterText(find.byType(TextField), 'error');
      await tester.pump(const Duration(milliseconds: 501));
      await tester.pumpAndSettle();
      expect(find.text('Retry search'), findsOneWidget);
      expect(find.text('1 selected'), findsOneWidget);
    },
  );
  testWidgets(
    'shared destinations count individual memberships, Back retains rooms',
    (tester) async {
      final s = FakeBatchInviteSource();
      await open(tester, s);
      await selectAll(tester, s);
      await tester.tap(find.text('Next: choose rooms'));
      await tester.pumpAndSettle();
      expect(find.text('Review 8 invitations'), findsOneWidget);
      await tester.tap(find.text('Space only'));
      await tester.pumpAndSettle();
      expect(find.text('Review 1 invitation'), findsOneWidget);
      await tester.tap(find.text('All available'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Review 8 invitations'));
      await tester.pumpAndSettle();
      expect(find.text('3 people · 8 invitations'), findsOneWidget);
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Review 8 invitations'), findsOneWidget);
      expect(s.sent, isEmpty);
    },
  );
  testWidgets('load failure and cancellation send nothing', (tester) async {
    final s = FakeBatchInviteSource()..failLoad = true;
    await open(tester, s);
    await selectAll(tester, s);
    await tester.tap(find.text('Next: choose rooms'));
    await tester.pumpAndSettle();
    expect(find.text('Retry loading rooms'), findsOneWidget);
    expect(s.sent, isEmpty);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(s.sent, isEmpty);
  });
  for (final style in LayoutStyle.values) {
    testWidgets('${style.name} phone at 150 percent keeps actions visible', (
      tester,
    ) async {
      await pickLayoutStyle(style);
      final s = FakeBatchInviteSource();
      await open(tester, s, scale: 1.5);
      tester.view.physicalSize = const Size(400, 900);
      await tester.pumpAndSettle();
      await selectAll(tester, s);
      await tester.tap(find.text('Next: choose rooms'));
      await tester.pumpAndSettle();
      expect(find.text('Review 8 invitations'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'sending uses fakes, reports partial failure and retries only that pair',
    (tester) async {
      final s = FakeBatchInviteSource()..failVoice = true;
      await open(tester, s);
      await selectAll(tester, s);
      await tester.tap(find.text('Next: choose rooms'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Review 8 invitations'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send 8 invitations'));
      await tester.pumpAndSettle();
      expect(s.sent.length, 8);
      expect(find.text('Invitation results'), findsOneWidget);
      s.failVoice = false;
      await tester.tap(
        find.text('Retry 1 failed invitation'),
      );
      await tester.pumpAndSettle();
      expect(s.sent.length, 9);
      expect(s.sent.last.$2, '!voice');
      expect(s.sent.last.$1, s.people.last.id);
    },
  );
  testWidgets('room review retains the earlier-message opt out', (
    tester,
  ) async {
    final s = FakeBatchInviteSource(isSpace: false);
    await open(tester, s);
    await selectAll(tester, s);
    await tester.tap(find.text('Review invitations'));
    await tester.pumpAndSettle();
    expect(find.text('Share earlier messages'), findsOneWidget);
    expect(s.sent, isEmpty);
  });
  testWidgets('large selections are visibly limited without truncating picks',
      (tester) async {
    final source = ManyDestinations();
    await open(tester, source);
    await tester
        .tap(find.byKey(ValueKey('invite-person-${source.people.last.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next: choose rooms'));
    await tester.pumpAndSettle();
    expect(find.text('Review 102 invitations'), findsOneWidget);
    expect(
        tester
            .widget<ElevatedButton>(
                find.widgetWithText(ElevatedButton, 'Review 102 invitations'))
            .onPressed,
        isNull);
    expect(source.sent, isEmpty);
    await tester.tap(find.text('Space only'));
    await tester.pumpAndSettle();
    expect(find.text('Review 1 invitation'), findsOneWidget);
  });
  testWidgets('existing-member history is optional and never sends invitations',
      (tester) async {
    final source = ExistingMembers();
    await open(tester, source);
    await tester
        .tap(find.byKey(ValueKey('invite-person-${source.people.first.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next: choose rooms'));
    await tester.pumpAndSettle();
    // Places that only offer a history share aren't ticked by default.
    expect(find.text('Review history sharing'), findsOneWidget);
    expect(
        tester
            .widget<ElevatedButton>(
                find.widgetWithText(ElevatedButton, 'Review history sharing'))
            .onPressed,
        isNull);
    await tester.tap(find.text('General'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review history sharing'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<ElevatedButton>(
                find.widgetWithText(ElevatedButton, 'Share history'))
            .onPressed,
        isNull);
    await tester.ensureVisible(
        find.text('Also share earlier messages with existing members'));
    await tester
        .tap(find.text('Also share earlier messages with existing members'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Share history'));
    await tester.pumpAndSettle();
    expect(source.sent.length, 1);
    expect(source.sent.single.$3, InviteOperation.history);
  });
  testWidgets('manual IDs reject aliases and empty localparts without sending',
      (tester) async {
    final source = FakeBatchInviteSource();
    source.searcher = (_) async => [];
    await open(tester, source);
    for (final query in ['#room:example.org', '@:example.org']) {
      await tester.enterText(find.byType(TextField), query);
      await tester.pump(const Duration(milliseconds: 501));
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('invite-person-$query')), findsNothing);
    }
    await tester.enterText(find.byType(TextField), '@NewFriend:example.org');
    await tester.pump(const Duration(milliseconds: 501));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('invite-person-@NewFriend:example.org')),
        findsOneWidget);
    expect(source.sent, isEmpty);
  });
  testWidgets(
      'a directory failure still permits selecting an exact valid Matrix ID',
      (tester) async {
    final source = FakeBatchInviteSource();
    source.searcher = (_) async => throw StateError('directory disabled');
    await open(tester, source);
    await tester.enterText(find.byType(TextField), '@KnownFriend:example.org');
    await tester.pump(const Duration(milliseconds: 501));
    await tester.pumpAndSettle();
    expect(find.text('Retry search'), findsOneWidget);
    final row =
        find.byKey(const ValueKey('invite-person-@KnownFriend:example.org'));
    await tester.ensureVisible(row);
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(find.text('1 selected'), findsOneWidget);
    expect(source.sent, isEmpty);
  });
  testWidgets(
      'unencrypted rooms preserve the server-history explanation without an ineffective opt out',
      (tester) async {
    final source = UnencryptedRoom();
    await open(tester, source);
    await tester
        .tap(find.byKey(ValueKey('invite-person-${source.people.first.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review invitations'));
    await tester.pumpAndSettle();
    expect(
        find.text(
            'In unencrypted rooms, the server shows earlier messages as each room’s history setting allows.'),
        findsOneWidget);
    expect(find.text('Share earlier messages'), findsNothing);
    expect(source.sent, isEmpty);
  });
  InvitationBatchTask sentTask() =>
      backgroundTaskManager.tasks.whereType<InvitationBatchTask>().single;
  Future<void> pick(WidgetTester tester, String id) async {
    final row = find.byKey(ValueKey('invite-person-$id'));
    await tester.ensureVisible(row);
    await tester.tap(row);
    await tester.pumpAndSettle();
  }

  testWidgets(
      'people who cannot be invited to a chosen room are skipped, not failures',
      (tester) async {
    final s = PerPersonRooms();
    await open(tester, s);
    await pick(tester, s.people[1].id);
    await pick(tester, s.people[2].id);
    await tester.tap(find.text('Next: choose rooms'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review 5 invitations'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send 5 invitations'));
    await tester.pumpAndSettle();
    final task = sentTask();
    final game = task.items
        .singleWhere((i) => i.userId == s.people[1].id && i.roomId == '!game');
    expect(game.outcome, InviteOutcome.skipped);
    expect(task.needsAttention, isFalse);
    expect(task.canRetry, isFalse);
    expect(s.sent.length, 5);
  });
  testWidgets('rooms nobody selected can be invited to drop out of the batch',
      (tester) async {
    final s = PerPersonRooms();
    await open(tester, s);
    await pick(tester, s.people[2].id);
    await tester.tap(find.text('Next: choose rooms'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    await pick(tester, s.people[2].id);
    await pick(tester, s.people[1].id);
    await tester.tap(find.text('Next: choose rooms'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review 1 invitation'));
    await tester.pumpAndSettle();
    expect(find.text('Game night'), findsNothing);
    await tester.tap(find.text('Send 1 invitation'));
    await tester.pumpAndSettle();
    final task = sentTask();
    expect(task.items.map((i) => i.roomId).toSet(), {s.rootId, '!general'});
    expect(task.needsAttention, isFalse);
  });
  testWidgets('rooms are invited even when the space itself cannot be',
      (tester) async {
    final s = NoSpacePower();
    await open(tester, s);
    await pick(tester, s.people[2].id);
    await tester.tap(find.text('Next: choose rooms'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review 3 invitations'));
    await tester.pumpAndSettle();
    expect(find.textContaining('to the space itself'), findsOneWidget);
    await tester.tap(find.text('Send 3 invitations'));
    await tester.pumpAndSettle();
    expect(s.sent.map((k) => k.$2).toSet(), {'!general', '!game', '!voice'});
    expect(sentTask().count(InviteOutcome.held), 0);
  });
  test('a request held by another batch says so, not waiting for its parent',
      () async {
    final s = FakeBatchInviteSource();
    final gate = Completer<void>();
    s.onSend = (_) => gate.future;
    BatchInviteItem jordan() => BatchInviteItem(
        userId: s.people[2].id, roomId: s.rootId, roomName: s.rootName);
    final a = s.task([jordan()]);
    final b = s.task([jordan()]);
    final run = a.start();
    await b.start();
    final view = InvitationBatchView(task: b, people: const {});
    expect(b.items.single.outcome, InviteOutcome.held);
    expect(view.stateLabel(b.items.single), 'In another invitation batch');
    gate.complete();
    await run;
    a.dispose();
    b.dispose();
  });
}
