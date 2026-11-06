// Drives .vommet/it/peers/js/peer.mjs (matrix-js-sdk + Rust crypto) as a
// child process: its stdout is one JSON object per line, {"peer": event}.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

class JsPeer {
  JsPeer._(this._process, this.name) {
    _process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      if (!line.startsWith('{')) return;
      try {
        final event = jsonDecode(line) as Map<String, Object?>;
        if (event['peer'] == null) return;
        _log('$name < $line');
        _seen.add(event);
        _changed.add(null);
      } catch (_) {}
    });
    _process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(stderr.add);
    _process.exitCode.then((code) {
      exitCode = code;
      _changed.add(null);
    });
  }

  final Process _process;
  final String name;
  final _seen = <Map<String, Object?>>[];
  final _changed = StreamController<void>.broadcast();
  final List<String> stderr = [];
  int? exitCode;
  var _cursor = 0;

  static void Function(String) log = print;
  void _log(String s) => log(s.length > 300 ? '${s.substring(0, 300)}...' : s);

  /// Starts the peer for [user]. [node]: the node binary; [script]: peer.mjs.
  static Future<JsPeer> start({
    required String node,
    required String script,
    required String homeserver,
    required String user,
    required String password,
    List<String> args = const [],
    Map<String, String>? environment,
    String? name,
  }) async {
    final process = await Process.start(
      node,
      [
        script,
        '--hs',
        homeserver,
        '--user',
        user,
        '--password',
        password,
        ...args,
      ],
      environment: environment,
    );
    final peer = JsPeer._(process, name ?? 'js-peer($user)');
    await peer.next('synced', timeout: const Duration(seconds: 90));
    return peer;
  }

  /// Every event seen so far.
  List<Map<String, Object?>> get events => List.unmodifiable(_seen);

  /// Waits for the next [event] (after the ones already returned by
  /// [next]) matching [where]. An `error` event or the process ending fails.
  Future<Map<String, Object?>> next(
    String event, {
    bool Function(Map<String, Object?>)? where,
    Duration timeout = const Duration(seconds: 120),
  }) async {
    final end = DateTime.now().add(timeout);
    while (true) {
      for (var i = _cursor; i < _seen.length; i++) {
        final e = _seen[i];
        if (e['peer'] == event && (where == null || where(e))) {
          _cursor = i + 1;
          return e;
        }
        if (e['peer'] == 'error') {
          _cursor = i + 1;
          throw StateError('$name failed: ${e['message']}');
        }
      }
      if (exitCode != null) {
        throw StateError('$name exited ($exitCode) waiting for $event: '
            '${stderr.reversed.take(20).toList().reversed.join('\n')}');
      }
      final left = end.difference(DateTime.now());
      if (left.isNegative) {
        throw TimeoutException('$name: no "$event"');
      }
      await _changed.stream.first.timeout(left, onTimeout: () {});
    }
  }

  /// Runs one stdin command and returns its answer [answer].
  Future<Map<String, Object?>> command(
    Map<String, Object?> cmd,
    String answer, {
    Duration timeout = const Duration(seconds: 120),
  }) {
    _log('$name > ${jsonEncode(cmd)}');
    _process.stdin.writeln(jsonEncode(cmd));
    return next(answer, where: (e) => e['cmd'] == cmd['cmd'], timeout: timeout);
  }

  Future<void> stop() async {
    try {
      await _process.stdin.close();
    } catch (_) {}
    await _process.exitCode.timeout(const Duration(seconds: 5), onTimeout: () {
      _process.kill();
      return -1;
    });
  }
}
