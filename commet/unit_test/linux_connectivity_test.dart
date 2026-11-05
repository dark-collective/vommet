import 'dart:async';
import 'dart:io';

import 'package:commet/utils/linux_connectivity.dart';
import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

/// A source whose check returns [result], throws [error] or never answers.
class FakeSource implements ConnectivitySource {
  FakeSource(this.name, {this.result, this.error, this.hangs = false});

  @override
  final String name;
  List<ConnectivityResult>? result;
  Object? error;
  bool hangs;
  int checks = 0;
  final updatesController =
      StreamController<List<ConnectivityResult>>.broadcast();

  @override
  Future<List<ConnectivityResult>> check() {
    checks++;
    if (hangs) return Completer<List<ConnectivityResult>>().future;
    if (error != null) return Future.error(error!);
    return Future.value(result ?? const []);
  }

  @override
  Stream<List<ConnectivityResult>> get updates => updatesController.stream;
}

/// Behaves like connectivity_plus's Linux backend with no system bus: the
/// error escapes to the zone and the future never completes.
class NoBusPlatform extends ConnectivityPlatform {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() {
    Future(() => throw const SocketException("no system bus"));
    return Completer<List<ConnectivityResult>>().future;
  }

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      StreamController<List<ConnectivityResult>>(
              onListen: () =>
                  Future(() => throw const SocketException("no system bus")))
          .stream;
}

class WorkingPlatform extends ConnectivityPlatform {
  final updates = StreamController<List<ConnectivityResult>>();

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async =>
      [ConnectivityResult.wifi];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => updates.stream;
}

const _short = Duration(milliseconds: 50);

void main() {
  group("checkConnectivity", () {
    test("uses the first source that answers", () async {
      final nm = FakeSource("nm", result: [ConnectivityResult.wifi]);
      final portal = FakeSource("portal", result: [ConnectivityResult.other]);
      final c = LinuxConnectivity([nm, portal], timeout: _short);

      expect(await c.checkConnectivity(), [ConnectivityResult.wifi]);
      expect(portal.checks, 0);
    });

    test("reports offline when the source says so", () async {
      final portal = FakeSource("portal", result: [ConnectivityResult.none]);
      final c = LinuxConnectivity([portal], timeout: _short);

      expect(await c.checkConnectivity(), [ConnectivityResult.none]);
    });

    test("falls back when a source throws (no NetworkManager on the bus)",
        () async {
      final nm = FakeSource("nm", error: Exception("ServiceUnknown"));
      final portal = FakeSource("portal", result: [ConnectivityResult.none]);
      final c = LinuxConnectivity([nm, portal], timeout: _short);

      expect(await c.checkConnectivity(), [ConnectivityResult.none]);
    });

    test("falls back when a source never answers (no system bus)", () async {
      final nm = FakeSource("nm", hangs: true);
      final portal = FakeSource("portal", result: [ConnectivityResult.other]);
      final c = LinuxConnectivity([nm, portal], timeout: _short);

      expect(await c.checkConnectivity(), [ConnectivityResult.other]);
    });

    test("counts as online when no source answers", () async {
      final portal = FakeSource("portal", hangs: true);
      final c = LinuxConnectivity([portal], timeout: _short);

      final result = await c.checkConnectivity();
      expect(result, isNot(contains(ConnectivityResult.none)));
      expect(result, isNotEmpty);
    });

    test("doesn't ask a failed source again", () async {
      final nm = FakeSource("nm", hangs: true);
      final portal = FakeSource("portal", result: [ConnectivityResult.other]);
      final c = LinuxConnectivity([nm, portal], timeout: _short);

      await c.checkConnectivity();
      await c.checkConnectivity();
      expect(nm.checks, 1);
      expect(portal.checks, 2);
    });

    test("an empty answer counts as online", () async {
      final portal = FakeSource("portal", result: []);
      final c = LinuxConnectivity([portal], timeout: _short);

      expect(await c.checkConnectivity(), LinuxConnectivity.assumeOnline);
    });
  });

  group("onConnectivityChanged", () {
    test("starts with the current state, then follows the source", () async {
      final portal = FakeSource("portal", result: [ConnectivityResult.other]);
      final c = LinuxConnectivity([portal], timeout: _short);

      final seen = <List<ConnectivityResult>>[];
      final sub = c.onConnectivityChanged.listen(seen.add);
      await pumpEventQueue();
      portal.updatesController.add([ConnectivityResult.none]);
      portal.updatesController.add([ConnectivityResult.other]);
      await pumpEventQueue();
      await sub.cancel();

      expect(seen, [
        [ConnectivityResult.other],
        [ConnectivityResult.none],
        [ConnectivityResult.other],
      ]);
      expect(portal.updatesController.hasListener, isFalse);
    });

    test("follows the fallback source when the first fails", () async {
      final nm = FakeSource("nm", error: Exception("ServiceUnknown"));
      final portal = FakeSource("portal", result: [ConnectivityResult.other]);
      final c = LinuxConnectivity([nm, portal], timeout: _short);

      final seen = <List<ConnectivityResult>>[];
      final sub = c.onConnectivityChanged.listen(seen.add);
      await pumpEventQueue();
      nm.updatesController.add([ConnectivityResult.none]);
      portal.updatesController.add([ConnectivityResult.none]);
      await pumpEventQueue();
      await sub.cancel();

      expect(nm.updatesController.hasListener, isFalse);
      expect(seen, [
        [ConnectivityResult.other],
        [ConnectivityResult.none],
      ]);
    });

    test("emits online once when no source answers", () async {
      final portal = FakeSource("portal", hangs: true);
      final c = LinuxConnectivity([portal], timeout: _short);

      final seen = <List<ConnectivityResult>>[];
      final errors = <Object>[];
      final sub = c.onConnectivityChanged.listen(seen.add, onError: errors.add);
      await Future.delayed(_short * 3);
      await sub.cancel();

      expect(seen, [LinuxConnectivity.assumeOnline]);
      expect(errors, isEmpty);
    });

    test("an update error keeps the last state and drops the source", () async {
      final nm = FakeSource("nm", result: [ConnectivityResult.ethernet]);
      final portal = FakeSource("portal", result: [ConnectivityResult.other]);
      final c = LinuxConnectivity([nm, portal], timeout: _short);

      final seen = <List<ConnectivityResult>>[];
      final errors = <Object>[];
      final sub = c.onConnectivityChanged.listen(seen.add, onError: errors.add);
      await pumpEventQueue();
      nm.updatesController.addError(Exception("bus went away"));
      await pumpEventQueue();
      await sub.cancel();

      expect(seen, [
        [ConnectivityResult.ethernet]
      ]);
      expect(errors, isEmpty);
      expect(await c.checkConnectivity(), [ConnectivityResult.other]);
    });
  });

  test("the portal's GetAvailable maps to online or offline", () {
    expect(PortalConnectivitySource.resultsFor(available: true),
        [ConnectivityResult.other]);
    expect(PortalConnectivitySource.resultsFor(available: false),
        [ConnectivityResult.none]);
  });

  group("NetworkManagerConnectivitySource", () {
    test("a check that would hang without a system bus fails at once",
        () async {
      final source = NetworkManagerConnectivitySource(NoBusPlatform());
      await expectLater(source.check(), throwsA(isA<SocketException>()));
    });

    test("updates without a system bus arrive as a stream error", () async {
      final source = NetworkManagerConnectivitySource(NoBusPlatform());
      await expectLater(source.updates, emitsError(isA<SocketException>()));
    });

    test("passes NetworkManager's answers through", () async {
      final platform = WorkingPlatform();
      final source = NetworkManagerConnectivitySource(platform);
      expect(await source.check(), [ConnectivityResult.wifi]);

      final next = source.updates.first;
      platform.updates.add([ConnectivityResult.ethernet]);
      expect(await next, [ConnectivityResult.ethernet]);
    });

    test("without a system bus LinuxConnectivity moves on to the portal",
        () async {
      final portal = FakeSource("portal", result: [ConnectivityResult.none]);
      final c = LinuxConnectivity(
          [NetworkManagerConnectivitySource(NoBusPlatform()), portal],
          timeout: const Duration(seconds: 30));

      expect(await c.checkConnectivity(), [ConnectivityResult.none]);
    });
  });
}
