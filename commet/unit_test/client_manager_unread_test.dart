// Vommet issue 949: the tray, the Linux notifier and the room header only
// listen to onUnreadChanged, so a logged-out account's counts stayed until
// another account synced (forever when it was the last account).
import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/client/client_manager.dart';
import 'package:commet/client/components/profile/profile_component.dart';
import 'package:commet/client/timeline_events/timeline_event.dart';
import 'package:commet/main.dart';
import 'package:commet/utils/stored_stream_controller.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/unread_fixtures.dart';

class Me extends Fake implements Profile {
  @override
  String get displayName => 'Me';
  @override
  String get identifier => '@me:test';
  @override
  ImageProvider? get avatar => null;
}

class Account extends UnreadClient {
  @override
  Profile? self = Me();
  @override
  Stream<(Room, TimelineEvent)> get onTimelineEvent => const Stream.empty();
  @override
  Stream<Space> get onSpaceAdded => const Stream.empty();
  @override
  Stream<Space> get onSpaceRemoved => const Stream.empty();
  @override
  final connectionStatusChanged =
      StoredStreamController<ClientConnectionStatusUpdate>();
  bool logoutFails = false;
  @override
  Future<void> logout() async {
    if (logoutFails) throw StateError('server refused logout');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Vommet issue 1139: drive the actual manager, including failed sign-out.
  test('removing an account clears magnet trust', () async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    final storage = await SharedPreferences.getInstance();
    const key = 'vommet_trusted_magnet_senders';
    await storage
        .setStringList(key, ['account|%40me%3Atest|%40alex%3Aexample.net']);
    final client = Account();
    ClientManager().removeClient(client);
    await Future<void>.delayed(Duration.zero);
    expect(storage.containsKey(key), isFalse);
    await client.close();
  });
  for (final fails in [false, true]) {
    test('logout clears magnet trust even when server fails=$fails', () async {
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues({});
      await preferences.init();
      final storage = await SharedPreferences.getInstance();
      const key = 'vommet_trusted_magnet_senders';
      await storage
          .setStringList(key, ['account|%40me%3Atest|%40alex%3Aexample.net']);
      final manager = ClientManager();
      final client = Account()..logoutFails = fails;
      manager.addClient(client);
      await manager.logoutClient(client);
      expect(storage.containsKey(key), isFalse);
      await client.close();
    });
  }

  test('adding and logging out an account publishes an unread change',
      () async {
    final manager = ClientManager();
    final client = Account();
    addTearDown(client.close);
    UnreadRoom(client, 'room', notificationCount: 2);
    final added = manager.onUnreadChanged.stream.first;
    manager.addClient(client);
    await added;
    // Let the new account's first index pass publish before logging out.
    await Future<void>.delayed(Duration.zero);
    var accounts = -1;
    final removed = manager.onUnreadChanged.stream.first
        .then((_) => accounts = manager.clients.length);
    await manager.logoutClient(client);
    await removed;
    expect(accounts, 0);
  });
}
