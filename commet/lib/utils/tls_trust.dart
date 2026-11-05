import 'dart:io';

import 'package:commet/config/platform_utils.dart';
import 'package:commet/debug/log.dart';

/// Vommet issue 990: TLS diagnostics for dart:io (all HTTP, incl. the Matrix
/// SDK, the call's JWT service and the LiveKit WebSocket).
///
/// A HandshakeException doesn't say which server it came from, so errors
/// like "CERTIFICATE_VERIFY_FAILED: unable to get local issuer certificate"
/// were impossible to act on. Every certificate verification failure is
/// recorded (host, port, issuer), and the error the user sees names it.
/// Verification itself is unchanged.
class TlsTrust {
  static Future<void>? _installing;

  static final List<TlsFailure> _failures = [];

  static const failureWindow = Duration(minutes: 1);

  /// Call once per isolate before any network use. Never throws.
  static Future<void> install() =>
      _installing ??= PlatformUtils.isWeb ? Future.value() : _install();

  static Future<void> _install() async {
    // Process-wide for this isolate. Another HttpOverrides.global set later
    // would silently drop the failure recording (verification stays as is).
    HttpOverrides.global = _TlsTrustHttpOverrides();
  }

  static void recordFailure(X509Certificate? cert, String host, int port,
      {DateTime? now}) {
    final failure = TlsFailure(host, port,
        subject: cert?.subject,
        issuer: cert?.issuer,
        time: now ?? DateTime.now());
    _failures.add(failure);
    if (_failures.length > 20) _failures.removeAt(0);
    Log.w("TLS certificate verification failed for ${failure.server} "
        "(subject: ${failure.subject}, issuer: ${failure.issuer})");
  }

  /// The certificate failures of the last [failureWindow], oldest first.
  static List<TlsFailure> recentFailures({DateTime? now}) {
    final at = now ?? DateTime.now();
    _failures.removeWhere((f) => at.difference(f.time) > failureWindow);
    return List.unmodifiable(_failures);
  }

  static bool isCertificateFailure(Object error) =>
      error is HandshakeException &&
      error.toString().contains("CERTIFICATE_VERIFY_FAILED");

  /// The text to show for [error]. A certificate verification failure names
  /// the server(s) whose certificate failed in the last minute; those
  /// failures are then used up, so a later error can't be blamed on them.
  /// Other errors are returned as their plain text.
  static String describeError(Object error, {DateTime? now}) {
    final text = error.toString();
    if (!isCertificateFailure(error)) return text;
    final failures = recentFailures(now: now);
    if (failures.isEmpty) return text;
    _failures.clear();

    final servers = <String, TlsFailure>{};
    for (final f in failures.reversed) {
      servers.putIfAbsent(f.server, () => f);
    }
    if (servers.length == 1) {
      final f = servers.values.single;
      final by = f.issuer == null ? "" : " (issued by ${f.issuer})";
      return "Couldn't verify the TLS certificate of ${f.server}$by.\n\n$text";
    }
    return "Couldn't verify the TLS certificate of one of these servers: "
        "${servers.keys.join(", ")}.\n\n$text";
  }
}

class TlsFailure {
  final String host;
  final int port;
  final String? subject;
  final String? issuer;
  final DateTime time;

  TlsFailure(this.host, this.port,
      {this.subject, this.issuer, required this.time});

  String get server => port == 443 ? host : "$host:$port";
}

class _TlsTrustHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    // Only records the failure: returning false keeps rejecting the
    // certificate, exactly as without a callback.
    client.badCertificateCallback = (cert, host, port) {
      TlsTrust.recordFailure(cert, host, port);
      return false;
    };
    return client;
  }
}
