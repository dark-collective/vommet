import 'package:commet/client/client.dart';
import 'package:commet/client/client_manager.dart';
import 'package:commet/main.dart' as app;
import 'package:commet/ui/organisms/overlay_windows/overlay_window_manager.dart';
import 'package:commet/ui/pages/main/desktop_room_history.dart';
import 'package:commet/ui/pages/main/main_page.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:tiamat/config/style/theme_dark.dart';

import 'support/room_page_fixtures.dart' as fixture;

class _FakeClient extends Fake implements Client {
  _FakeClient(this.identifier);
  @override
  final String identifier;
}

class _FakeRoom extends Fake implements Room {
  _FakeRoom(this.identifier, this.client);
  @override
  final String identifier;
  @override
  final Client client;
}

class _HistoryClientManager extends ClientManager {
  @override
  bool isLoggedIn() => false; // Suppress startup setup screens in this fixture.
}

void main() {
  testWidgets('real desktop page handles side buttons and respects dialogs',
      (tester) async {
    await tester.runAsync(fixture.roomPageSetUp);
    addTearDown(() => tester.runAsync(fixture.roomPageTearDown));
    await app.preferences.layoutOverride.set('desktop');
    final manager = _HistoryClientManager()..callManager.playSounds = false;
    manager.clients.add(fixture.roomPageClient);
    app.clientManager = manager;
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(Provider<ClientManager>.value(
      value: manager,
      child: MaterialApp(
        theme: ThemeDark.theme,
        home: OverlayWindowsManager(child: MainPage(manager)),
      ),
    ));
    await fixture.settle(tester);
    final page = tester.state<MainPageState>(find.byType(MainPage));
    final first = fixture.roomPageClient.getRoom(fixture.callRoom)!;
    final second = fixture.roomPageClient.getRoom(fixture.emptyRoom)!;

    Future<void> click(int buttons) async {
      await tester.tapAt(const Offset(900, 300),
          buttons: buttons, kind: PointerDeviceKind.mouse);
      await fixture.settle(tester);
    }

    await click(kBackMouseButton);
    expect(page.currentRoom, isNull);
    page.selectRoom(first, bypassSpecialRoomType: true);
    await fixture.settle(tester);
    page.selectRoom(second);
    await fixture.settle(tester);

    await click(kBackMouseButton | kPrimaryButton);
    expect(page.currentRoom, second);
    await click(kBackMouseButton);
    expect(page.currentRoom, first);
    expect(page.showAsTextRoom, isTrue);
    await click(kForwardMouseButton);
    expect(page.currentRoom, second);
    expect(page.showAsTextRoom, isFalse);

    final dialog = showDialog<void>(
      context: page.context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(content: Text('Keep this room')),
    );
    await tester.pumpAndSettle();
    await click(kBackMouseButton);
    expect(page.currentRoom, second);
    expect(find.text('Keep this room'), findsOneWidget);
    Navigator.of(page.context).pop();
    await dialog;
    await tester.pumpAndSettle();

    page.clearRoomSelection();
    await fixture.settle(tester);
    await click(kBackMouseButton);
    expect(page.currentRoom, second);
    await click(kBackMouseButton);
    expect(page.currentRoom, first);
    await fixture.finishRoomPage(tester);
  });

  final clientA = _FakeClient('client_a');
  final clientB = _FakeClient('client_b');

  final room1 = _FakeRoom('!room1:example.org', clientA);
  final room2 = _FakeRoom('!room2:example.org', clientA);
  final room3 = _FakeRoom('!room3:example.org', clientA);
  final room4 = _FakeRoom('!room4:example.org', clientB);

  group('DesktopRoomHistory unit tests', () {
    test('initial state is empty with no back or forward', () {
      final history = DesktopRoomHistory();
      expect(history.length, 0);
      expect(history.currentIndex, -1);
      expect(history.currentEntry, isNull);
      expect(history.canGoBack(), isFalse);
      expect(history.canGoForward(), isFalse);
      expect(history.goBack(), isNull);
      expect(history.goForward(), isNull);
    });

    test('browser-style back and forward navigation stack', () {
      final history = DesktopRoomHistory();
      history.record(room1);
      expect(history.length, 1);
      expect(history.currentIndex, 0);
      expect(history.canGoBack(), isFalse);
      expect(history.canGoForward(), isFalse);

      history.record(room2);
      history.record(room3);
      expect(history.length, 3);
      expect(history.currentIndex, 2);
      expect(history.canGoBack(), isTrue);
      expect(history.canGoForward(), isFalse);
      expect(history.currentEntry?.roomId, room3.identifier);

      // Back to room 2
      final back1 = history.goBack();
      expect(back1?.roomId, room2.identifier);
      expect(history.currentIndex, 1);
      expect(history.canGoBack(), isTrue);
      expect(history.canGoForward(), isTrue);

      // Back to room 1
      final back2 = history.goBack();
      expect(back2?.roomId, room1.identifier);
      expect(history.currentIndex, 0);
      expect(history.canGoBack(), isFalse);
      expect(history.canGoForward(), isTrue);

      // Back at root returns null
      expect(history.goBack(), isNull);
      expect(history.currentIndex, 0);

      // Forward to room 2
      final forward1 = history.goForward();
      expect(forward1?.roomId, room2.identifier);
      expect(history.currentIndex, 1);
      expect(history.canGoBack(), isTrue);
      expect(history.canGoForward(), isTrue);

      // Forward to room 3
      final forward2 = history.goForward();
      expect(forward2?.roomId, room3.identifier);
      expect(history.currentIndex, 2);
      expect(history.canGoBack(), isTrue);
      expect(history.canGoForward(), isFalse);

      // Forward at end returns null
      expect(history.goForward(), isNull);
      expect(history.currentIndex, 2);
    });

    test(
        'forward history is cleared when opening a new room from an earlier position',
        () {
      final history = DesktopRoomHistory();
      history.record(room1);
      history.record(room2);
      history.record(room3);

      // Go back to room 2
      history.goBack();
      expect(history.currentIndex, 1);
      expect(history.canGoForward(), isTrue);

      // User opens room 4 from room 2
      history.record(room4);
      expect(history.length, 3); // room1, room2, room4
      expect(history.currentIndex, 2);
      expect(history.currentEntry?.roomId, room4.identifier);
      expect(history.canGoForward(), isFalse);

      final prev = history.goBack();
      expect(prev?.roomId, room2.identifier);
    });

    test(
        'consecutive duplicate room selections update metadata without creating duplicate entries',
        () {
      final history = DesktopRoomHistory();
      history.record(room1, spaceId: 'space_1', showAsTextRoom: false);
      expect(history.length, 1);
      expect(history.currentEntry?.showAsTextRoom, isFalse);
      expect(history.currentEntry?.spaceId, 'space_1');

      // Toggling view mode in the same room updates in place
      history.record(room1, spaceId: 'space_1', showAsTextRoom: true);
      expect(history.length, 1);
      expect(history.currentIndex, 0);
      expect(history.currentEntry?.showAsTextRoom, isTrue);

      // Re-recording identical state is a no-op
      history.record(room1, spaceId: 'space_1', showAsTextRoom: true);
      expect(history.length, 1);
    });

    test(
        'isCurrentRoomNull reopens current entry on first back before traversing earlier',
        () {
      final history = DesktopRoomHistory();
      history.record(room1);
      history.record(room2);

      // User clears room selection (views space overview or home screen)
      expect(history.canGoBack(isCurrentRoomNull: true), isTrue);
      final restored = history.goBack(isCurrentRoomNull: true);
      expect(restored?.roomId, room2.identifier);
      expect(history.currentIndex, 1);

      // Subsequent back goes to room 1
      final earlier = history.goBack(isCurrentRoomNull: false);
      expect(earlier?.roomId, room1.identifier);
      expect(history.currentIndex, 0);
    });

    test('skips and prunes invalid or left rooms during navigation', () {
      final history = DesktopRoomHistory();
      history.record(room1);
      history.record(room2);
      history.record(room3);

      // Room 2 was left / no longer valid
      bool isValid(DesktopRoomHistoryEntry entry) =>
          entry.roomId != room2.identifier;

      final back = history.goBack(isValid: isValid);
      expect(back?.roomId, room1.identifier);
      expect(history.length, 2);
      expect(history.entries.map((e) => e.roomId),
          [room1.identifier, room3.identifier]);

      final forward = history.goForward(isValid: isValid);
      expect(forward?.roomId, room3.identifier);
    });

    test(
        'onRoomRemoved and pruneClients adjust index and prune matching entries',
        () {
      final history = DesktopRoomHistory();
      history.record(room1);
      history.record(room2);
      history.record(room4);
      expect(history.currentIndex, 2);

      // Remove room2 from middle
      history.onRoomRemoved(room2.identifier);
      expect(history.length, 2);
      expect(history.currentIndex, 1);
      expect(history.currentEntry?.roomId, room4.identifier);

      // Prune clientB
      history.pruneClients({clientA.identifier});
      expect(history.length, 1);
      expect(history.currentIndex, 0);
      expect(history.currentEntry?.roomId, room1.identifier);
    });

    test('Back from an overview opens the nearest surviving room', () {
      final history = DesktopRoomHistory()
        ..record(room1)
        ..record(room2)
        ..record(room3);

      final restored = history.goBack(
        isCurrentRoomNull: true,
        isValid: (entry) => entry.roomId != room3.identifier,
      );
      expect(restored?.roomId, room2.identifier);
    });

    for (final removeAccount in [false, true]) {
      test(
        'Back after removing the current ${removeAccount ? 'account' : 'room'}'
        ' keeps the forward entry ahead',
        () {
          final history = DesktopRoomHistory()
            ..record(room1)
            ..record(room4)
            ..record(room3);
          expect(history.goBack()?.roomId, room4.identifier);

          if (removeAccount) {
            history.pruneClients({clientA.identifier});
          } else {
            history.onRoomRemoved(room4.identifier, clientB.identifier);
          }

          expect(
            history.goBack(isCurrentRoomNull: true)?.roomId,
            room1.identifier,
          );
          expect(history.goForward()?.roomId, room3.identifier);
        },
      );
    }

    test('bounds history size to maxEntries', () {
      final history = DesktopRoomHistory(maxEntries: 3);
      history.record(room1);
      history.record(room2);
      history.record(room3);
      history.record(room4);

      expect(history.length, 3);
      expect(history.currentIndex, 2);
      expect(history.entries.map((e) => e.roomId), [
        room2.identifier,
        room3.identifier,
        room4.identifier,
      ]);
    });

    test('remembers spaceId and showAsTextRoom metadata per entry', () {
      final history = DesktopRoomHistory();
      history.record(room1, spaceId: 'space_alpha', showAsTextRoom: true);
      history.record(room2, spaceId: 'space_beta', showAsTextRoom: false);

      final back = history.goBack();
      expect(back?.roomId, room1.identifier);
      expect(back?.spaceId, 'space_alpha');
      expect(back?.showAsTextRoom, isTrue);

      final forward = history.goForward();
      expect(forward?.roomId, room2.identifier);
      expect(forward?.spaceId, 'space_beta');
      expect(forward?.showAsTextRoom, isFalse);
    });

    test('DesktopRoomHistoryEntry equality, hashCode and toString', () {
      final a1 = DesktopRoomHistoryEntry(
        roomId: '!r1:example.org',
        clientId: 'client_1',
        spaceId: 'space_1',
        showAsTextRoom: true,
      );
      final a2 = DesktopRoomHistoryEntry(
        roomId: '!r1:example.org',
        clientId: 'client_1',
        spaceId: 'space_1',
        showAsTextRoom: true,
      );
      final b = DesktopRoomHistoryEntry(
        roomId: '!r2:example.org',
        clientId: 'client_1',
        spaceId: 'space_1',
        showAsTextRoom: true,
      );

      expect(a1, equals(a2));
      expect(a1.hashCode, equals(a2.hashCode));
      expect(a1, isNot(equals(b)));
      expect(a1.toString(), contains('!r1:example.org'));
    });

    test('clear resets history stack completely', () {
      final history = DesktopRoomHistory();
      history.record(room1);
      history.record(room2);
      expect(history.length, 2);

      history.clear();
      expect(history.length, 0);
      expect(history.currentIndex, -1);
      expect(history.currentEntry, isNull);
    });
  });

  group('DesktopRoomHistoryHost widget tests', () {
    testWidgets('mouse back button triggers onNavigateBack', (tester) async {
      var backCalled = 0;
      var forwardCalled = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: DesktopRoomHistoryHost(
            onNavigateBack: () {
              backCalled++;
              return true;
            },
            onNavigateForward: () {
              forwardCalled++;
              return true;
            },
            child: const Scaffold(
              body: SizedBox(
                width: 800,
                height: 600,
                child: Text('Desktop App Content'),
              ),
            ),
          ),
        ),
      );

      // Simulate mouse back button click (kBackMouseButton = 0x08)
      final center = tester.getCenter(find.text('Desktop App Content'));
      final backDown = PointerDownEvent(
        pointer: 1,
        kind: PointerDeviceKind.mouse,
        buttons: kBackMouseButton,
        position: center,
      );
      await tester.sendEventToBinding(backDown);
      await tester.sendEventToBinding(PointerUpEvent(
        pointer: 1,
        kind: PointerDeviceKind.mouse,
        position: center,
      ));
      await tester.pump();

      expect(backCalled, 1);
      expect(forwardCalled, 0);
    });

    testWidgets('mouse forward button triggers onNavigateForward',
        (tester) async {
      var backCalled = 0;
      var forwardCalled = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: DesktopRoomHistoryHost(
            onNavigateBack: () {
              backCalled++;
              return true;
            },
            onNavigateForward: () {
              forwardCalled++;
              return true;
            },
            child: const Scaffold(
              body: SizedBox(
                width: 800,
                height: 600,
                child: Text('Desktop App Content'),
              ),
            ),
          ),
        ),
      );

      // Simulate mouse forward button click (kForwardMouseButton = 0x10)
      final center = tester.getCenter(find.text('Desktop App Content'));
      final forwardDown = PointerDownEvent(
        pointer: 1,
        kind: PointerDeviceKind.mouse,
        buttons: kForwardMouseButton,
        position: center,
      );
      await tester.sendEventToBinding(forwardDown);
      await tester.sendEventToBinding(PointerUpEvent(
        pointer: 1,
        kind: PointerDeviceKind.mouse,
        position: center,
      ));
      await tester.pump();

      expect(backCalled, 0);
      expect(forwardCalled, 1);
    });

    testWidgets('primary left-click, right-click and touch events are ignored',
        (tester) async {
      var backCalled = 0;
      var forwardCalled = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: DesktopRoomHistoryHost(
            onNavigateBack: () {
              backCalled++;
              return true;
            },
            onNavigateForward: () {
              forwardCalled++;
              return true;
            },
            child: const Scaffold(
              body: SizedBox(
                width: 800,
                height: 600,
                child: Text('Desktop App Content'),
              ),
            ),
          ),
        ),
      );

      final center = tester.getCenter(find.text('Desktop App Content'));

      // Primary mouse button (left click)
      await tester.sendEventToBinding(PointerDownEvent(
        pointer: 1,
        kind: PointerDeviceKind.mouse,
        buttons: kPrimaryMouseButton,
        position: center,
      ));
      await tester.sendEventToBinding(PointerUpEvent(
        pointer: 1,
        kind: PointerDeviceKind.mouse,
        position: center,
      ));

      // Secondary mouse button (right click)
      await tester.sendEventToBinding(PointerDownEvent(
        pointer: 2,
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
        position: center,
      ));
      await tester.sendEventToBinding(PointerUpEvent(
        pointer: 2,
        kind: PointerDeviceKind.mouse,
        position: center,
      ));

      // Touch tap
      await tester.sendEventToBinding(PointerDownEvent(
        pointer: 3,
        kind: PointerDeviceKind.touch,
        buttons: kPrimaryButton,
        position: center,
      ));
      await tester.sendEventToBinding(PointerUpEvent(
        pointer: 3,
        kind: PointerDeviceKind.touch,
        position: center,
      ));
      await tester.pump();

      expect(backCalled, 0);
      expect(forwardCalled, 0);
    });

    test(
        'DesktopRoomHistoryHost.handlePointerDown returns true only for mouse back/forward',
        () {
      var backCalled = 0;
      var forwardCalled = 0;
      bool onBack() {
        backCalled++;
        return true;
      }

      bool onForward() {
        forwardCalled++;
        return true;
      }

      // Back mouse button
      final handledBack = DesktopRoomHistoryHost.handlePointerDown(
        const PointerDownEvent(
          kind: PointerDeviceKind.mouse,
          buttons: kBackMouseButton,
        ),
        onNavigateBack: onBack,
        onNavigateForward: onForward,
      );
      expect(handledBack, isTrue);
      expect(backCalled, 1);
      expect(forwardCalled, 0);

      // Forward mouse button
      final handledForward = DesktopRoomHistoryHost.handlePointerDown(
        const PointerDownEvent(
          kind: PointerDeviceKind.mouse,
          buttons: kForwardMouseButton,
        ),
        onNavigateBack: onBack,
        onNavigateForward: onForward,
      );
      expect(handledForward, isTrue);
      expect(backCalled, 1);
      expect(forwardCalled, 1);

      // Left click
      final handledLeft = DesktopRoomHistoryHost.handlePointerDown(
        const PointerDownEvent(
          kind: PointerDeviceKind.mouse,
          buttons: kPrimaryMouseButton,
        ),
        onNavigateBack: onBack,
        onNavigateForward: onForward,
      );
      expect(handledLeft, isFalse);

      // Touch back button (non-mouse device)
      final handledTouch = DesktopRoomHistoryHost.handlePointerDown(
        const PointerDownEvent(
          kind: PointerDeviceKind.touch,
          buttons: kBackMouseButton,
        ),
        onNavigateBack: onBack,
        onNavigateForward: onForward,
      );
      expect(handledTouch, isFalse);
    });
  });
}
