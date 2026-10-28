// Turn errors into telemetry fields without their messages: exception text
// can quote message bodies, file names or user IDs, so only the error's Dart
// type, a fixed error category and source locations are ever kept.

import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart' as matrix;

class TelemetryErrors {
  /// One of the schema's `error_kind` values.
  static String kind(Object? error) {
    if (error == null) return "none";
    // Vommet: the SDK wraps a failed /sync request's exception; classify
    // what is inside (a dropped connection, a timeout, a TLS failure ...).
    // These showed up as "unknown" and were most of the sync errors seen.
    if (error is matrix.SyncConnectionException) {
      return kind(error.originalException);
    }
    if (error is TimeoutException) return "timeout";
    if (error is HandshakeException || error is TlsException) return "tls";
    if (error is SocketException || error is http.ClientException) {
      return "network";
    }
    if (error is matrix.MatrixException) {
      // Vommet (schema v22): the SDK builds API errors from the JSON body
      // only (MatrixException.fromJson), so `response` is null and every
      // one of them used to come out "unknown". Fall back to what the
      // Matrix error code says.
      return httpKind(error.response?.statusCode) ??
          _errcodeKinds[error.raw["errcode"]] ??
          "unknown";
    }
    // The SDK's error for an HTTP error response without a Matrix error
    // body (e.g. a proxy's 502/504 page after a long wait). Its text is a
    // fixed phrase from the SDK, never server or user content.
    if (isBareHttpError(error)) return "http_error";
    if (error is FileSystemException) return "storage";
    if (error is FormatException) return "decode";
    if (error is OutOfMemoryError) return "out_of_memory";
    if (error is UnsupportedError || error is UnimplementedError) {
      return "unsupported";
    }
    if (error is StateError) return "state";
    return "unknown";
  }

  static const _errcodeKinds = {
    "M_FORBIDDEN": "http_403",
    "M_NOT_FOUND": "http_404",
    "M_UNKNOWN_TOKEN": "http_401",
    "M_MISSING_TOKEN": "http_401",
    "M_LIMIT_EXCEEDED": "http_429",
    "M_TOO_LARGE": "http_413",
  };

  /// True for the SDK's `Exception('http error response')`: the server
  /// answered with an HTTP error whose body wasn't a Matrix error, and the
  /// SDK kept neither the status nor the body.
  static bool isBareHttpError(Object? error) =>
      error is Exception &&
      error.toString() == "Exception: http error response";

  /// error_kind/http_status for a bare SDK HTTP error whose [status] was
  /// recovered from the http client (null when it wasn't).
  static Map<String, Object?> bareHttpFields(int? status) => {
        "error_kind": httpKind(status) ?? "http_error",
        "http_status": status,
      };

  static String? httpKind(int? status) {
    if (status == null) return null;
    switch (status) {
      case 401:
        return "http_401";
      case 403:
        return "http_403";
      case 404:
        return "http_404";
      case 413:
        return "http_413";
      case 429:
        return "http_429";
    }
    if (status >= 500) return "http_5xx";
    if (status >= 400) return "http_4xx";
    return null;
  }

  static int? httpStatus(Object? error) {
    if (error is matrix.SyncConnectionException) {
      return httpStatus(error.originalException);
    }
    if (error is matrix.MatrixException) return error.response?.statusCode;
    return null;
  }

  /// Matrix error codes from the spec, kept as-is. Anything else (a
  /// server-specific code) becomes "other", so only fixed values are sent.
  static const knownErrcodes = {
    "M_FORBIDDEN",
    "M_UNKNOWN_TOKEN",
    "M_MISSING_TOKEN",
    "M_USER_LOCKED",
    "M_USER_SUSPENDED",
    "M_BAD_JSON",
    "M_NOT_JSON",
    "M_NOT_FOUND",
    "M_LIMIT_EXCEEDED",
    "M_UNRECOGNIZED",
    "M_UNKNOWN",
    "M_UNAUTHORIZED",
    "M_USER_DEACTIVATED",
    "M_USER_IN_USE",
    "M_INVALID_USERNAME",
    "M_ROOM_IN_USE",
    "M_INVALID_ROOM_STATE",
    "M_THREEPID_IN_USE",
    "M_THREEPID_NOT_FOUND",
    "M_THREEPID_AUTH_FAILED",
    "M_THREEPID_DENIED",
    "M_THREEPID_MEDIUM_NOT_SUPPORTED",
    "M_SERVER_NOT_TRUSTED",
    "M_UNSUPPORTED_ROOM_VERSION",
    "M_INCOMPATIBLE_ROOM_VERSION",
    "M_BAD_STATE",
    "M_GUEST_ACCESS_FORBIDDEN",
    "M_CAPTCHA_NEEDED",
    "M_CAPTCHA_INVALID",
    "M_MISSING_PARAM",
    "M_INVALID_PARAM",
    "M_TOO_LARGE",
    "M_EXCLUSIVE",
    "M_RESOURCE_LIMIT_EXCEEDED",
    "M_CANNOT_LEAVE_SERVER_NOTICE_ROOM",
    "M_WEAK_PASSWORD",
    "M_UNABLE_TO_AUTHORISE_JOIN",
    "M_UNABLE_TO_GRANT_JOIN",
    "M_NOT_YET_UPLOADED",
    "M_CANNOT_OVERWRITE_MEDIA",
    "M_WRONG_ROOM_KEYS_VERSION",
    "M_CONNECTION_FAILED",
    "M_CONNECTION_TIMEOUT",
    "M_UNACTIONABLE",
    "M_UNKNOWN_POS",
  };

  /// The server's Matrix error code (e.g. `M_FORBIDDEN`) for a Matrix API
  /// error, reduced to [knownErrcodes] or "other". Null for other errors.
  static String? errcode(Object? error) {
    if (error is matrix.SyncConnectionException) {
      return errcode(error.originalException);
    }
    if (error is! matrix.MatrixException) return null;
    final code = error.raw["errcode"];
    if (code is! String) return "other";
    return knownErrcodes.contains(code) ? code : "other";
  }

  static final _typeName = RegExp(r"^[A-Za-z_$][A-Za-z0-9_$<>, ?]{0,79}$");

  /// The error's Dart type name, e.g. `_TypeError`. Never its message.
  static String typeName(Object error) {
    final name = error.runtimeType.toString();
    return _typeName.hasMatch(name) ? name : "Object";
  }

  // "#3      MatrixRoom.sendMessage (package:commet/client/matrix/matrix_room.dart:539:7)"
  static final _frame = RegExp(
      r"^#\d+\s+(.+?) \(((?:package:[a-z0-9_]+/[A-Za-z0-9_/.\-]+\.dart)|(?:dart:[a-z_]+(?:/[a-z_]+\.dart)?)):(\d+)(?::\d+)?\)$");
  static final _symbol = RegExp(r"[^A-Za-z0-9_$.<>]");

  // Release builds made with --split-debug-info (the Android APK) print
  // non-symbolic traces: a header with the program's build id, then frames
  // like "#00 abs 0000007a2c8b3d0f virt 00000000002c1d0f
  // _kDartIsolateSnapshotInstructions+0x209d0f". The symbol + offset pair is
  // all `flutter symbolize` needs (with the build's symbols file), and it is
  // a position in Vommet's own program, nothing else.
  static final _buildId = RegExp(r"build_id(?:=|: )'([0-9a-f]{8,64})'");
  static final _isolateBase =
      RegExp(r"isolate_instructions(?:=|: )([0-9a-f]+)");
  static final _vmBase = RegExp(r"vm_instructions(?:=|: )([0-9a-f]+)");
  static final _pcLine = RegExp(r"^#\d+ abs ([0-9a-f]+)(?: unit \d+)?"
      r"(?: virt [0-9a-f]+)?(?: (.*))?$");
  static final _symbolOffset =
      RegExp(r"^_kDart(Isolate|Vm)SnapshotInstructions\+(?:0x)?([0-9a-f]+)$");

  /// The build id and frame offsets of a non-symbolic Dart stack trace:
  /// each frame as "i+<hex>" (isolate instructions) or "v+<hex>" (VM
  /// instructions). Null when [trace] is a symbolic trace or has neither.
  static ({String buildId, List<String> pcs})? dartPcs(StackTrace? trace,
      {int max = 40}) {
    if (trace == null) return null;
    final text = trace.toString();
    final id = _buildId.firstMatch(text)?.group(1);
    if (id == null) return null;
    final isolateBase =
        int.tryParse(_isolateBase.firstMatch(text)?.group(1) ?? "", radix: 16);
    final vmBase =
        int.tryParse(_vmBase.firstMatch(text)?.group(1) ?? "", radix: 16);
    final pcs = <String>[];
    for (final raw in text.split("\n")) {
      final m = _pcLine.firstMatch(raw.trim());
      if (m == null) continue;
      final sym = _symbolOffset.firstMatch((m.group(2) ?? "").trim());
      String? pc;
      if (sym != null) {
        final off = int.tryParse(sym.group(2)!, radix: 16);
        if (off != null) {
          pc =
              "${sym.group(1) == "Isolate" ? "i" : "v"}+${off.toRadixString(16)}";
        }
      } else {
        // No symbol printed: work it out from the header's base addresses.
        final abs = int.tryParse(m.group(1)!, radix: 16);
        if (abs != null && isolateBase != null && abs >= isolateBase) {
          pc = "i+${(abs - isolateBase).toRadixString(16)}";
        } else if (abs != null && vmBase != null && abs >= vmBase) {
          pc = "v+${(abs - vmBase).toRadixString(16)}";
        }
      }
      if (pc != null && pc.length <= 14) pcs.add(pc);
      if (pcs.length >= max) break;
    }
    if (pcs.isEmpty) return null;
    return (buildId: id, pcs: pcs);
  }

  /// Source locations (file:line function) from a stack trace, at most [max].
  /// Paths outside packages (e.g. a home directory) are left out entirely.
  static List<String> frames(StackTrace? trace, {int max = 25}) {
    if (trace == null) return const [];
    final out = <String>[];
    for (final line in trace.toString().split("\n")) {
      final m = _frame.firstMatch(line.trim());
      if (m == null) continue;
      var fn = m.group(1)!.replaceAll(_symbol, "_");
      if (fn.length > 120) fn = fn.substring(0, 120);
      out.add("${m.group(2)}:${m.group(3)} $fn");
      if (out.length >= max) break;
    }
    return out;
  }
}
