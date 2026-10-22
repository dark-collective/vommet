import 'package:commet/client/components/emoticon/emoticon_component.dart';
import 'dart:async';

import 'package:commet/client/alert.dart';
import 'package:commet/client/call_manager.dart';
import 'package:commet/client/client.dart';
import 'package:commet/client/components/direct_messages/direct_message_aggregator.dart';
import 'package:commet/client/components/direct_messages/direct_message_component.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/stale_info.dart';
import 'package:commet/client/tasks/client_connection_status_task.dart';
import 'package:commet/client/tasks/connection_badge_grace.dart';
import 'package:commet/client/timeline_events/timeline_event.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/main.dart';
import 'package:commet/utils/android_call_task.dart';
import 'package:commet/utils/notifying_list.dart';

class ClientManager {
  final Map<String, Client> _clients = {};

  final NotifyingList<Room> _rooms = NotifyingList.empty(growable: true);

  final NotifyingList<Space> _spaces = NotifyingList.empty(growable: true);

  final AlertManager alertManager = AlertManager();
  late CallManager callManager;

  final StreamController<(Client, Room, TimelineEvent)> _onEventReceived =
      StreamController.broadcast();

  Stream<(Client, Room, TimelineEvent)> get onEventReceived =>
      _onEventReceived.stream;

  late final DirectMessagesAggregator directMessages;

  ClientManager() {
    directMessages = DirectMessagesAggregator(this);
    callManager = CallManager(this);
    // Vommet issue 285: swiping the app away hangs up (Android).
    AndroidCallTask.attach(callManager.currentSessions);
  }

  NotifyingList<Room> get rooms => _rooms;

  List<Room> singleRooms({Client? filterClient}) {
    var result = List<Room>.empty(growable: true);
    for (var client in clients) {
      if (filterClient != null && client != filterClient) {
        continue;
      }

      var dmComp = client.getComponent<DirectMessagesComponent>();

      for (var room in client.rooms) {
        if (dmComp != null) {
          if (dmComp.isRoomDirectMessage(room)) {
            continue;
          }
        }

        if (client.spaces.any((space) => space.containsRoom(room.identifier))) {
          continue;
        }

        // Vommet: sticker rooms live under Settings › Emoticons.
        if (isStickerRoom(room)) continue;

        result.add(room);
      }
    }

    return result;
  }

  List<Space> get spaces => _spaces;

  final NotifyingList<Client> _clientsList =
      NotifyingList.empty(growable: true);
  final Map<Client, List<StreamSubscription>> _clientSubscriptions = {};
  final Set<Client> _clientsLoggingOut = {};

  NotifyingList<Client> get clients => _clientsList;

  late StreamController<void> onSync = StreamController.broadcast();

  Stream<Room> get onRoomAdded => _rooms.onAdd;

  Stream<Room> get onRoomRemoved => _rooms.onRemove;

  Stream<Space> get onSpaceAdded => _spaces.onAdd;

  Stream<Space> get onSpaceRemoved => _spaces.onRemove;

  late StreamController<int> onClientAdded = StreamController.broadcast();

  late StreamController<StalePeerInfo> onClientRemoved =
      StreamController.broadcast();

  late StreamController<Space> onSpaceUpdated = StreamController.broadcast();
  late StreamController<Space> onSpaceChildUpdated =
      StreamController.broadcast();

  late StreamController<Room> onRoomUpdated = StreamController.broadcast();

  late StreamController<Room> onDirectMessageRoomUpdated =
      StreamController.broadcast();

  // int get directMessagesNotificationCount => directMessages.fold(
  //     0,
  //     (previousValue, element) =>
  //         previousValue + element.displayNotificationCount);

  static Future<ClientManager> init({bool isBackgroundService = false}) async {
    final newClientManager = ClientManager();

    await Future.wait([
      MatrixClient.loadFromDB(newClientManager,
          isBackgroundService: isBackgroundService),
    ]);

    return newClientManager;
  }

  /// Vommet: see [Client.startupLoadsDone].
  ///
  /// Awaited rather than returned: Future.wait's result is a
  /// Future<List<void>>, and its timeout() would reject a void onTimeout
  /// callback at runtime (a crash at startup when the 20 s cap is hit).
  Future<void> waitForStartupLoads() async {
    await Future.wait(_clientsList.map((c) => c.startupLoadsDone));
  }

  void addClient(Client client) {
    try {
      _clients[client.identifier] = client;

      _clientsList.add(client);

      for (final e in client.rooms) {
        _onClientAddedRoom(client, e);
      }

      for (final e in client.spaces) {
        _addSpace(client, e);
      }

      // Vommet: a sync that fails once and recovers doesn't flash the
      // "disconnected" badge.
      final badgeGrace = ConnectionBadgeGrace(
          show: (status) => _onClientConnectionStatusChanged(client, status));

      _clientSubscriptions[client] = [
        client.onSync.listen((_) {
          badgeGrace.onSync();
          _badgeDismissed.remove(client);
          _synced();
        }),
        client.onTimelineEvent
            .listen((i) => _onEventReceived.add((client, i.$1, i.$2))),
        client.onRoomAdded.listen((room) => _onClientAddedRoom(client, room)),
        client.onRoomRemoved
            .listen((room) => _onClientRemovedRoom(client, room)),
        client.onSpaceAdded.listen((space) => _addSpace(client, space)),
        client.onSpaceRemoved
            .listen((space) => _onClientRemovedSpace(client, space)),
        client.connectionStatusChanged.stream.listen(badgeGrace.onStatus),
      ];

      onClientAdded.add(_clients.length - 1);
    } catch (error) {}
  }

  /// Vommet: accounts whose connection badge the user clicked away.
  final Set<Client> _badgeDismissed = {};

  void _onClientConnectionStatusChanged(
      Client client, ClientConnectionStatusUpdate status) {
    if (status.status == ClientConnectionStatus.connected) {
      return;
    }

    // A grace timer can still fire after the account was logged out.
    if (!_clientsList.contains(client)) return;

    // Vommet: a badge the user clicked away stays hidden until the next
    // successful sync, rather than coming back on the next retry.
    if (_badgeDismissed.contains(client)) return;

    if (backgroundTaskManager.tasks
        .whereType<ClientConnectionStatusTask>()
        .where((element) => element.client == client)
        .isEmpty) {
      backgroundTaskManager.addTask(ClientConnectionStatusTask(client, status,
          onDismissed: () => _badgeDismissed.add(client)));
    }
  }

  void _onClientAddedRoom(Client client, Room room) {
    rooms.add(room);
    room.onUpdate.listen((_) => roomUpdated(room));
  }

  void _onClientRemovedRoom(Client client, Room room) {
    _rooms.remove(room);
  }

  void _onClientRemovedSpace(Client client, Space space) {
    _spaces.remove(space);
  }

  void _addSpace(Client client, Space space) {
    space.onUpdate.listen((_) => spaceUpdated(space));
    space.onChildRoomUpdated.listen((_) => spaceChildUpdated(space));
    spaces.add(space);
  }

  void spaceUpdated(Space space) {
    onSpaceUpdated.add(space);
  }

  void spaceChildUpdated(Space space) {
    onSpaceChildUpdated.add(space);
  }

  void roomUpdated(Room room) {
    onRoomUpdated.add(room);
  }

  void directMessageRoomUpdated(Room room) {
    onDirectMessageRoomUpdated.add(room);
  }

  Future<void> logoutClient(Client client) async {
    int clientIndex = _clientsList.indexOf(client);
    // A second tap while the first logout is still running would announce the
    // removal twice
    if (clientIndex == -1 || !_clientsLoggingOut.add(client)) return;

    _badgeDismissed.remove(client);

    var subs = _clientSubscriptions[client];
    if (subs != null) {
      for (var sub in subs) {
        sub.cancel();
      }
      _clientSubscriptions.remove(client);
    }

    var clientInfo = StalePeerInfo(
        index: clientIndex,
        displayName: client.self!.displayName,
        identifier: client.self!.identifier,
        avatar: client.self!.avatar);

    for (int i = rooms.length - 1; i >= 0; i--) {
      if (rooms[i].client == client) {
        rooms.removeAt(i);
      }
    }

    for (int i = spaces.length - 1; i >= 0; i--) {
      if (spaces[i].client == client) {
        spaces.removeAt(i);
      }
    }

    // Vommet issue 321: an account that failed to load, or a server that
    // refuses the logout, made logout() throw, and the account stayed in the
    // list for good. Remove it here whatever the server says.
    try {
      await client.logout();
    } catch (error, trace) {
      Log.onError(error, trace,
          content: "Logout failed, removed the account locally anyway");
    } finally {
      onClientRemoved.add(clientInfo);
      _clients.remove(client.identifier);
      _clientsList.remove(client);
      _clientsLoggingOut.remove(client);
    }
  }

  void removeClient(Client client) {
    if (_clients.containsKey(client.identifier)) {
      _clients.remove(client.identifier);
    }

    if (_clientsList.contains(client)) {
      _clientsList.remove(client);
    }
  }

  bool isLoggedIn() {
    return _clients.values.any((element) => element.isLoggedIn());
  }

  Future<void> close() async {
    for (var client in _clients.values) {
      client.close();
    }
  }

  void _synced() {
    onSync.add(null);
  }

  Client? getClient(String identifier) {
    var search = clients.where((element) => element.identifier == identifier);
    if (search.isNotEmpty) return search.first;
    return null;
  }
}
