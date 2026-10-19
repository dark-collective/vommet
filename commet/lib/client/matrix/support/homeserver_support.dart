import 'dart:convert';

import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/debug/log.dart';

/// A server admin or security contact from `/.well-known/matrix/support`.
class HomeserverSupportContact {
  /// `m.role.admin`, `m.role.security`, or a namespaced custom role.
  final String role;
  final String? emailAddress;
  final String? matrixId;

  const HomeserverSupportContact(
      {required this.role, this.emailAddress, this.matrixId});
}

/// What a homeserver publishes at `/.well-known/matrix/support` (spec'd since
/// Matrix 1.10, MSC1929): a support page and admin contacts.
class HomeserverSupport {
  final Uri? supportPage;
  final List<HomeserverSupportContact> contacts;

  const HomeserverSupport({this.supportPage, this.contacts = const []});

  bool get isEmpty => supportPage == null && contacts.isEmpty;

  /// Lenient parse: unknown or malformed fields are skipped, and only
  /// http(s) support pages are accepted. Returns null when nothing usable.
  static HomeserverSupport? fromJson(Object? json) {
    if (json is! Map) return null;

    Uri? page;
    final rawPage = json["support_page"];
    if (rawPage is String) {
      final uri = Uri.tryParse(rawPage.trim());
      if (uri != null &&
          (uri.scheme == "https" || uri.scheme == "http") &&
          uri.host.isNotEmpty) {
        page = uri;
      }
    }

    final contacts = <HomeserverSupportContact>[];
    final rawContacts = json["contacts"];
    if (rawContacts is List) {
      for (final c in rawContacts) {
        if (c is! Map || c["role"] is! String) continue;
        final email = c["email_address"] is String
            ? (c["email_address"] as String).trim()
            : null;
        final mxid =
            c["matrix_id"] is String ? (c["matrix_id"] as String).trim() : null;
        if ((email == null || email.isEmpty) &&
            (mxid == null || mxid.isEmpty)) {
          continue;
        }
        contacts.add(HomeserverSupportContact(
            role: c["role"] as String,
            emailAddress: email?.isEmpty == true ? null : email,
            matrixId: mxid?.isEmpty == true ? null : mxid));
      }
    }

    final result = HomeserverSupport(supportPage: page, contacts: contacts);
    return result.isEmpty ? null : result;
  }

  /// The server name part of a user ID (`@a:example.org:8448` →
  /// `example.org:8448`), or null when [userId] has none.
  static String? serverNameOf(String? userId) {
    if (userId == null) return null;
    final colon = userId.indexOf(":");
    if (colon < 0 || colon == userId.length - 1) return null;
    return userId.substring(colon + 1);
  }

  /// The hostname of a server name, without any port: well-known files are
  /// served from the hostname (`example.org:8448` → `example.org`, and
  /// `[::1]:8448` → `::1`).
  static String hostOf(String serverName) {
    if (serverName.startsWith("[")) {
      final end = serverName.indexOf("]");
      return end > 0 ? serverName.substring(1, end) : serverName;
    }
    final colon = serverName.lastIndexOf(":");
    return colon >= 0 ? serverName.substring(0, colon) : serverName;
  }

  /// Fetches the support file for [client]'s server. The spec puts it on the
  /// server name's host (the part after ':' in the user ID); fall back to the
  /// homeserver's own URL, which is where some deployments serve it.
  static Future<HomeserverSupport?> fetch(MatrixClient client) async {
    final mx = client.getMatrixClient();
    final serverName = serverNameOf(mx.userID);
    final host = serverName != null ? hostOf(serverName) : null;

    final candidates = <Uri>[
      if (host != null && host.isNotEmpty)
        Uri.https(host, "/.well-known/matrix/support"),
      if (mx.homeserver != null)
        mx.homeserver!.resolve("/.well-known/matrix/support"),
    ];

    for (final uri in candidates.toSet()) {
      try {
        final response =
            await mx.httpClient.get(uri).timeout(const Duration(seconds: 10));
        if (response.statusCode != 200) continue;
        final result = fromJson(jsonDecode(utf8.decode(response.bodyBytes)));
        if (result != null) return result;
      } catch (e) {
        Log.i("No homeserver support info at $uri: $e");
      }
    }

    return null;
  }
}
