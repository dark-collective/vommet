// Vommet (schema v17): how long each kind of homeserver request takes, as
// 15-minute summaries per request family. Wraps the http client the Matrix
// SDK is given: one stopwatch per request and a byte count on the response
// body, nothing on the UI's critical path. The family comes from the shape
// of the URL's path only; the URL itself (room, user, event and media IDs,
// the server name) is never kept. Also notes the server's clock against
// ours, from the `Date` header of sync responses, for ordering and expiry
// problems that only show up with a skewed device clock.

import 'dart:async';
import 'dart:io';

import 'package:commet/telemetry/frame_stats.dart';
import 'package:commet/telemetry/telemetry.dart';
import 'package:http/http.dart' as http;

class _FamilyStats {
  final MsHistogram ms = MsHistogram();
  int errors = 0;
  int bytes = 0;
}

class HttpStats {
  /// The schema's `http_family` values, matched against the path only.
  static const List<(String, String)> _families = [
    // Sliding sync (MSC3575 / MSC4186) and classic /sync.
    (r"/sync$", "sync"),
    (r"/rooms/[^/]+/send/", "send"),
    (r"/rooms/[^/]+/redact/", "redact"),
    (r"/media/(download|v\d+/download)/", "media_download"),
    (r"/media/(thumbnail|v\d+/thumbnail)/", "media_thumbnail"),
    (r"/media/(upload|v\d+/upload|v\d+/create)", "media_upload"),
    (r"/keys/", "keys"),
    (r"/profile/", "profile"),
    (r"/rooms/[^/]+/state", "state"),
    (r"/rooms/[^/]+/messages$", "messages"),
    (r"/rooms/[^/]+/(members|joined_members)$", "members"),
    (r"/push(ers|rules)", "push"),
    (r"/account_data/", "account_data"),
    (r"/rooms/[^/]+/context/", "context"),
    (r"/(join|rooms/[^/]+/join)", "join"),
    (r"/login", "login"),
    (r"/\.well-known/", "well_known"),
    (r"/voip/|/_matrix/client/[^/]+/org\.matrix\.msc4143", "voip"),
  ];
  static final List<(RegExp, String)> _compiled = [
    for (final (p, f) in _families) (RegExp(p), f)
  ];

  static String family(String path) {
    for (final (re, f) in _compiled) {
      if (re.hasMatch(path)) return f;
    }
    return "other";
  }

  static final Map<String, _FamilyStats> _stats = {};

  /// Seconds the server's clock is ahead of ours (negative: behind), from
  /// the most recent sync response; null until one has been seen.
  static int? clockSkewS;

  /// Vommet (v32): body bytes of the most recently read sync response (as
  /// read, so after decompression), for the first_sync event. Read when
  /// the SDK starts applying that response, which is after the body ended.
  static int? lastSyncBytes;

  static void add(String family, bool? ownServer, int ms,
      {bool error = false, int bytes = 0}) {
    if (!Telemetry.enabled) return;
    final key = "$family|${ownServer ?? "?"}";
    final s = _stats.putIfAbsent(key, _FamilyStats.new);
    s.ms.add(ms);
    if (error) s.errors++;
    s.bytes += bytes;
  }

  /// Vommet (schema v22): the last HTTP error status per request family,
  /// with a running number, so an operation can recover the status the SDK
  /// throws away (see TelemetryErrors.isBareHttpError). Only error
  /// responses touch this.
  static int errorSeq = 0;
  static final Map<String, (int, int)> _lastError = {};

  static void noteErrorStatus(String family, int status) {
    errorSeq++;
    _lastError[family] = (errorSeq, status);
  }

  /// The status of the latest [family] error response after [seq] (an
  /// earlier [errorSeq]), or null when there was none.
  static int? errorStatusSince(String family, int seq) {
    final last = _lastError[family];
    if (last == null || last.$1 <= seq) return null;
    return last.$2;
  }

  static void noteServerDate(String? header) {
    if (header == null) return;
    try {
      final skew = HttpDate.parse(header).difference(DateTime.now()).inSeconds;
      clockSkewS = skew.clamp(-31536000, 31536000);
    } catch (_) {}
  }

  static void report() {
    for (final MapEntry(key: key, value: s) in _stats.entries) {
      final parts = key.split("|");
      Telemetry.record("http_stats", {
        "family": parts[0],
        if (parts[1] != "?") "own_server": parts[1] == "true",
        "requests": s.ms.count.clamp(0, 1000000),
        "errors": s.errors.clamp(0, 1000000),
        "p95_ms": s.ms.p95().clamp(0, 86400000),
        "worst_ms": s.ms.worstMs.clamp(0, 86400000),
        "bytes_rx": s.bytes.clamp(0, 1099511627776),
      });
    }
    reset();
  }

  static void reset() => _stats.clear();

  static void clearErrors() => _lastError.clear();
}

/// An http client that records each request's family, duration, outcome and
/// response size with [HttpStats]. Hand it to the SDK (`httpClient:`) or
/// wrap a one-off client with [TelemetryHttpClient.wrap].
class TelemetryHttpClient extends http.BaseClient {
  final http.Client _inner;

  /// Whether requests through this client go to the user's own server
  /// (see SyncStats.onOwnServer); null when not known.
  bool? Function()? ownServer;

  TelemetryHttpClient(this._inner, {this.ownServer});

  static http.Client wrap(http.Client inner) =>
      Telemetry.enabled ? TelemetryHttpClient(inner) : inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (!Telemetry.enabled) return _inner.send(request);
    final family = HttpStats.family(request.url.path);
    final own = ownServer?.call();
    final clock = Stopwatch()..start();
    final http.StreamedResponse response;
    try {
      response = await _inner.send(request);
    } catch (_) {
      HttpStats.add(family, own, clock.elapsedMilliseconds, error: true);
      rethrow;
    }
    if (family == "sync") HttpStats.noteServerDate(response.headers["date"]);
    if (response.statusCode >= 400) {
      HttpStats.noteErrorStatus(family, response.statusCode);
    }
    var bytes = 0;
    var done = false;
    void finish({bool error = false}) {
      if (done) return;
      done = true;
      if (family == "sync" && !error && response.statusCode < 400) {
        HttpStats.lastSyncBytes = bytes;
      }
      HttpStats.add(family, own, clock.elapsedMilliseconds,
          error: error || response.statusCode >= 400, bytes: bytes);
    }

    final body = response.stream.transform(
      StreamTransformer<List<int>, List<int>>.fromHandlers(
        handleData: (chunk, sink) {
          bytes += chunk.length;
          sink.add(chunk);
        },
        handleError: (e, st, sink) {
          finish(error: true);
          sink.addError(e, st);
        },
        handleDone: (sink) {
          finish();
          sink.close();
        },
      ),
    );
    return http.StreamedResponse(
      http.ByteStream(body),
      response.statusCode,
      contentLength: response.contentLength,
      request: response.request,
      headers: response.headers,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
      reasonPhrase: response.reasonPhrase,
    );
  }

  @override
  void close() => _inner.close();
}
