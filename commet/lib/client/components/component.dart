import 'package:commet/client/client.dart';
import 'package:commet/client/timeline_events/timeline_event.dart';
import 'package:commet/main.dart';
import 'package:flutter/widgets.dart';

abstract class Component<T extends Client> {
  final T client;
  Component(this.client);
}

abstract class EventHandlerComponent {
  bool canHandleEvent(TimelineEvent eventType);

  Widget? displayTimelineEvent(
    TimelineEvent event, {
    required String senderName,
  });
}

/// Vommet: components holding timers or stream subscriptions on their
/// client implement this, so closing the client (logout, removing an
/// account, a test's teardown) stops them before the database closes.
abstract class NeedsCloseOnClientClose {
  Future<void> onClientClosed();
}

abstract class NeedsPostLoginInit {
  void postLoginInit();

  static void doPostLoginInit() {
    for (var client in clientManager!.clients) {
      if (!client.isLoggedIn()) continue;

      var components = client.getAllComponents()!;

      for (var component in components) {
        if (component is! NeedsPostLoginInit) continue;

        (component as NeedsPostLoginInit).postLoginInit();
      }

      for (var room in client.rooms) {
        for (var component in room.getAllComponents()) {
          if (component is! NeedsPostLoginInit) continue;

          (component as NeedsPostLoginInit).postLoginInit();
        }
      }
    }
  }
}
