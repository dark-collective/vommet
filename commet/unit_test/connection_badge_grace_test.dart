import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/client/tasks/connection_badge_grace.dart';
import 'package:test/test.dart';

class _FakeTimer implements Timer {
  _FakeTimer(this.duration, this.callback);

  final Duration duration;
  final void Function() callback;
  bool cancelled = false;

  void fire() {
    if (!cancelled) callback();
  }

  @override
  void cancel() => cancelled = true;

  @override
  bool get isActive => !cancelled;

  @override
  int get tick => 0;
}

void main() {
  late List<ClientConnectionStatus> shown;
  late List<_FakeTimer> timers;
  late ConnectionBadgeGrace grace;

  ClientConnectionStatusUpdate update(ClientConnectionStatus status) =>
      ClientConnectionStatusUpdate(status);

  setUp(() {
    shown = [];
    timers = [];
    grace = ConnectionBadgeGrace(
      show: (u) => shown.add(u.status),
      timer: (duration, callback) {
        final timer = _FakeTimer(duration, callback);
        timers.add(timer);
        return timer;
      },
    );
  });

  test("before the first sync the badge shows straight away", () {
    grace.onStatus(update(ClientConnectionStatus.connecting));
    expect(shown, [ClientConnectionStatus.connecting]);
    expect(timers, isEmpty);
  });

  test("connected never shows the badge", () {
    grace.onSync();
    grace.onStatus(update(ClientConnectionStatus.connected));
    expect(shown, isEmpty);
    expect(timers, isEmpty);
  });

  test("one failed sync that recovers shows nothing", () {
    grace.onSync();
    grace.onStatus(update(ClientConnectionStatus.disconnected));
    expect(shown, isEmpty);
    expect(timers.single.duration, const Duration(seconds: 20));

    grace.onSync();
    expect(timers.single.cancelled, isTrue);
    timers.single.fire();
    expect(shown, isEmpty);
  });

  test("repeated failures share one grace timer", () {
    grace.onSync();
    grace.onStatus(update(ClientConnectionStatus.disconnected));
    grace.onStatus(update(ClientConnectionStatus.connected));
    grace.onStatus(update(ClientConnectionStatus.disconnected));
    expect(timers, hasLength(1));
  });

  test("no sync for the whole grace shows disconnected", () {
    grace.onSync();
    grace.onStatus(update(ClientConnectionStatus.disconnected));
    // The retry's own status reads connected before its response arrives.
    grace.onStatus(update(ClientConnectionStatus.connected));
    timers.single.fire();
    expect(shown, [ClientConnectionStatus.disconnected]);
  });

  test("while overdue, further trouble shows at once until a sync", () {
    grace.onSync();
    grace.onStatus(update(ClientConnectionStatus.disconnected));
    timers.single.fire();
    grace.onStatus(update(ClientConnectionStatus.disconnected));
    expect(shown, [
      ClientConnectionStatus.disconnected,
      ClientConnectionStatus.disconnected,
    ]);
    expect(timers, hasLength(1));

    grace.onSync();
    grace.onStatus(update(ClientConnectionStatus.disconnected));
    expect(shown, hasLength(2));
    expect(timers, hasLength(2));
  });

  test("dispose cancels a pending timer", () {
    grace.onSync();
    grace.onStatus(update(ClientConnectionStatus.disconnected));
    grace.dispose();
    expect(timers.single.cancelled, isTrue);
  });
}
