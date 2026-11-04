// Vommet issue 949: the tray, the Linux notifier and the room header only
// listen to onUnreadChanged, so a logged-out account's counts stayed until
// another account synced (forever when it was the last account).
import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/client/client_manager.dart';
import 'package:commet/client/components/profile/profile_component.dart';
import 'package:commet/client/timeline_events/timeline_event.dart';
import 'package:commet/utils/stored_stream_controller.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

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
  @override
  Future<void> logout() async {}
}

void main() {
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
