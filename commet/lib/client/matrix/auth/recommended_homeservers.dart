import 'dart:convert';

import 'package:flutter/services.dart';

// Vommet: the homeservers offered on the "Create an account" screen. The
// list is a copy of nether.wiki's /matrix/homeservers.json, baked into each
// release so nothing is fetched before the user has picked a server.

enum HomeserverRegistration { open, token, invite }

class RecommendedHomeserver {
  final String server;
  final String summary;
  final HomeserverRegistration registration;
  final String? registrationNote;
  final bool calls;
  final List<String> tags;
  final Uri? infoUrl;

  /// The server run by the people who make Vommet.
  final bool us;

  const RecommendedHomeserver({
    required this.server,
    required this.summary,
    required this.registration,
    this.registrationNote,
    this.calls = false,
    this.tags = const [],
    this.infoUrl,
    this.us = false,
  });

  /// Null for an entry this version can't use (missing fields, or a
  /// registration kind added to the list after this release).
  static RecommendedHomeserver? fromJson(Map<String, dynamic> json) {
    final server = json["server"];
    final summary = json["summary"];
    final registration = HomeserverRegistration.values
        .where((e) => e.name == json["registration"])
        .firstOrNull;
    if (server is! String || summary is! String || registration == null) {
      return null;
    }

    final info = json["info_url"];
    final tags = json["tags"];
    final note = json["registration_note"];

    return RecommendedHomeserver(
      server: server,
      summary: summary,
      registration: registration,
      registrationNote: note is String ? note : null,
      calls: json["calls"] == true,
      tags: tags is List ? tags.whereType<String>().toList() : const [],
      infoUrl: info is String ? Uri.tryParse(info) : null,
      us: json["us"] == true,
    );
  }

  static List<RecommendedHomeserver> parseList(String source) {
    final json = jsonDecode(source);
    if (json is! Map || json["servers"] is! List) return [];

    return (json["servers"] as List)
        .whereType<Map<String, dynamic>>()
        .map(fromJson)
        .whereType<RecommendedHomeserver>()
        .toList();
  }

  static Future<List<RecommendedHomeserver>> load() async {
    final source = await rootBundle.loadString("assets/data/homeservers.json");
    return parseList(source);
  }
}
