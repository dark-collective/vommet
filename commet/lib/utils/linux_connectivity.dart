import 'dart:async';
import 'dart:io';

import 'package:commet/config/build_config.dart';
import 'package:commet/debug/log.dart';
import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
import 'package:dbus/dbus.dart';

/// Where [LinuxConnectivity] reads the network state from.
abstract class ConnectivitySource {
  String get name;
  Future<List<ConnectivityResult>> check();

  /// The state each time it changes.
  Stream<List<ConnectivityResult>> get updates;
}

/// connectivity_plus's own Linux backend, which asks NetworkManager on the
/// system bus. Knows the connection type (Wi-Fi, ethernet, ...).
class NetworkManagerConnectivitySource implements ConnectivitySource {
  NetworkManagerConnectivitySource(this.platform);
  final ConnectivityPlatform platform;

  @override
  String get name => "NetworkManager";

  // When the system bus can't be reached, connectivity_plus's futures never
  // complete and the error escapes to the zone instead, so both calls run in
  // a guarded zone that hands such errors back to the caller.
  @override
  Future<List<ConnectivityResult>> check() {
    final result = Completer<List<ConnectivityResult>>();
    runZonedGuarded(() async {
      final value = await platform.checkConnectivity();
      if (!result.isCompleted) result.complete(value);
    }, (e, s) {
      if (!result.isCompleted) result.completeError(e, s);
    });
    return result.future;
  }

  @override
  Stream<List<ConnectivityResult>> get updates {
    StreamSubscription<List<ConnectivityResult>>? subscription;
    late final StreamController<List<ConnectivityResult>> controller;
    controller = StreamController(
        onListen: () => runZonedGuarded(() {
              subscription = platform.onConnectivityChanged
                  .listen(controller.add, onError: controller.addError);
            }, controller.addError),
        onCancel: () => subscription?.cancel());
    return controller.stream;
  }
}

/// The desktop portal's NetworkMonitor on the session bus, which a Flatpak
/// may use without any system bus access. It only says whether the network
/// is up, not its type, so a working network reads as
/// [ConnectivityResult.other].
class PortalConnectivitySource implements ConnectivitySource {
  static const _interface = "org.freedesktop.portal.NetworkMonitor";

  DBusClient? _client;
  DBusRemoteObject get _portal {
    _client ??= DBusClient.session();
    return DBusRemoteObject(_client!,
        name: "org.freedesktop.portal.Desktop",
        path: DBusObjectPath("/org/freedesktop/portal/desktop"));
  }

  @override
  String get name => "portal NetworkMonitor";

  @override
  Future<List<ConnectivityResult>> check() async {
    final reply = await _portal.callMethod(_interface, "GetAvailable", [],
        replySignature: DBusSignature("b"));
    return resultsFor(available: reply.returnValues.first.asBoolean());
  }

  static List<ConnectivityResult> resultsFor({required bool available}) =>
      [available ? ConnectivityResult.other : ConnectivityResult.none];

  @override
  Stream<List<ConnectivityResult>> get updates => DBusRemoteObjectSignalStream(
          object: _portal, interface: _interface, name: "changed")
      .asyncMap((_) => check());
}

/// Linux connectivity that works without NetworkManager access (Vommet
/// issue 340). connectivity_plus's Linux backend reads NetworkManager over
/// the system bus; in a Flatpak without `--system-talk-name` its check
/// never completes, so LiveKit, which awaits it before joining a call,
/// stalled. The Flatpak asks the desktop portal instead; elsewhere
/// NetworkManager comes first and the portal second. When no source answers
/// the network counts as up, so a call is never blocked by the check.
class LinuxConnectivity extends ConnectivityPlatform {
  LinuxConnectivity(this.sources, {this.timeout = const Duration(seconds: 3)});

  /// In order of preference.
  final List<ConnectivitySource> sources;
  final Duration timeout;

  /// Sources that failed once; they aren't asked again (each try would
  /// cost [timeout] when the bus doesn't answer).
  final Set<ConnectivitySource> _failed = {};

  static const assumeOnline = [ConnectivityResult.other];

  static bool get inFlatpak =>
      BuildConfig.IS_FLATPAK || Platform.environment.containsKey("FLATPAK_ID");

  /// Replaces connectivity_plus's Linux backend (registered before main).
  static void install() {
    final networkManager =
        NetworkManagerConnectivitySource(ConnectivityPlatform.instance);
    final portal = PortalConnectivitySource();
    ConnectivityPlatform.instance =
        LinuxConnectivity(inFlatpak ? [portal] : [networkManager, portal]);
  }

  /// The first source that answers within [timeout], with its answer.
  Future<(ConnectivitySource?, List<ConnectivityResult>)> _read() async {
    for (final source in sources) {
      if (_failed.contains(source)) continue;
      try {
        final result = await source.check().timeout(timeout);
        return (source, result.isEmpty ? assumeOnline : result);
      } catch (e) {
        _failed.add(source);
        Log.w("Connectivity: ${source.name} unavailable ($e)");
      }
    }
    return (null, assumeOnline);
  }

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async =>
      (await _read()).$2;

  StreamController<List<ConnectivityResult>>? _controller;
  StreamSubscription<List<ConnectivityResult>>? _updates;

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged {
    _controller ??= StreamController<List<ConnectivityResult>>.broadcast(
        onListen: _listen, onCancel: _cancel);
    return _controller!.stream;
  }

  Future<void> _listen() async {
    final (source, result) = await _read();
    if (!(_controller?.hasListener ?? false)) return;
    _emit(result);
    if (source == null || _updates != null) return;

    _updates = source.updates.listen(_emit, onError: (Object e) {
      // Keep the last state; a later check tries the next source.
      _failed.add(source);
      Log.w("Connectivity: ${source.name} updates failed ($e)");
    });
  }

  void _emit(List<ConnectivityResult> result) {
    final controller = _controller;
    if (controller == null || !controller.hasListener) return;
    controller.add(result.isEmpty ? assumeOnline : result);
  }

  Future<void> _cancel() async {
    final updates = _updates;
    _updates = null;
    await updates?.cancel();
  }
}
