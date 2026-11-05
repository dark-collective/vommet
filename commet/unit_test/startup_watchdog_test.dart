import 'dart:async';

import 'package:commet/utils/startup_watchdog.dart';
import 'package:commet/utils/startup_watchdog/storage_probe.dart';
import 'package:flutter_test/flutter_test.dart';

const _mb = 1024 * 1024;
const _after = Duration(milliseconds: 50);

Future<void> _wait([int ms = 200]) =>
    Future.delayed(Duration(milliseconds: ms));

void main() {
  test("says so once when loading takes too long", () async {
    final messages = <String>[];
    final watchdog = StartupWatchdog(
      messages.add,
      after: _after,
      probe: () async => null,
    )..start();
    expect(messages, isEmpty);
    await _wait();
    expect(messages, [startupSlow]);
    watchdog.start();
    await _wait();
    expect(messages, [startupSlow]);
  });

  test("never fires once the app is shown", () async {
    final messages = <String>[];
    final watchdog = StartupWatchdog(
      messages.add,
      after: _after,
      probe: () async => null,
    )..start();
    watchdog.finished();
    await _wait();
    expect(messages, isEmpty);
  });

  test(
    "never fires if the app is shown while the storage probe runs",
    () async {
      final messages = <String>[];
      final probe = Completer<StorageEstimate?>();
      var probing = false;
      final watchdog = StartupWatchdog(
        messages.add,
        after: _after,
        probe: () {
          probing = true;
          return probe.future;
        },
      )..start();
      await _wait();
      expect(probing, isTrue);
      watchdog.finished();
      probe.complete(const StorageEstimate(0, 100 * _mb));
      await _wait(20);
      expect(messages, isEmpty);
    },
  );

  test("a failing probe still shows the plain message", () async {
    final messages = <String>[];
    StartupWatchdog(
      messages.add,
      after: _after,
      probe: () async => throw "no storage api",
    ).start();
    await _wait();
    expect(messages, [startupSlow]);
  });

  test("names small or full browser storage", () {
    expect(StartupWatchdog.messageFor(null), startupSlow);
    expect(
      StartupWatchdog.messageFor(const StorageEstimate(0, 0)),
      startupSlow,
    );
    expect(
      StartupWatchdog.messageFor(const StorageEstimate(10 * _mb, 300 * _mb)),
      startupSlowSmallStorage,
    );
    expect(
      StartupWatchdog.messageFor(
        const StorageEstimate(9500 * _mb, 10000 * _mb),
      ),
      startupSlowSmallStorage,
    );
    expect(
      StartupWatchdog.messageFor(const StorageEstimate(100 * _mb, 10000 * _mb)),
      startupSlow,
    );
  });
}
