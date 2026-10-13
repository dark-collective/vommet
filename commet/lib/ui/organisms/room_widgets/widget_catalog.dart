// Vommet: the widget catalog behind the "Add widget" tile. A copy of
// vommet.app/widgets/catalog.json ships in assets/data/widget_catalog.json,
// so opening the picker contacts no server.
import 'dart:convert';

import 'package:commet/client/components/widgets/widget_send_types.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

class CatalogWidget {
  const CatalogWidget({
    required this.id,
    required this.name,
    required this.by,
    required this.summary,
    required this.url,
    required this.icon,
    required this.tags,
    this.type,
    this.avatarMxc,
    this.previewMxc,
    this.sends = const [],
  });

  final String id;
  final String name;
  final String by;
  final String summary;
  final String url;
  final String icon;
  final List<String> tags;
  final String? type;
  final String? avatarMxc;
  final String? previewMxc;

  /// Vommet: the widget's send capabilities, from "sends" (event types) and
  /// "sends_state" (state event types), for the "View only" badge.
  final List<String> sends;

  static CatalogWidget? fromJson(Map<String, dynamic> j) {
    final id = j["id"], name = j["name"], url = j["url"];
    if (id is! String || name is! String || url is! String) return null;
    return CatalogWidget(
      id: id,
      name: name,
      by: j["by"] as String? ?? "",
      summary: j["summary"] as String? ?? "",
      url: url,
      icon: j["icon"] as String? ?? "",
      tags: (j["tags"] as List?)?.whereType<String>().toList() ?? const [],
      type: j["type"] as String?,
      avatarMxc: j["avatar_mxc"] as String?,
      previewMxc: j["preview_mxc"] as String?,
      sends: [
        for (final t in (j["sends"] as List?)?.whereType<String>() ?? [])
          "${WidgetSendTypes.sendEvent}:$t",
        for (final t in (j["sends_state"] as List?)?.whereType<String>() ?? [])
          "${WidgetSendTypes.sendState}:$t",
      ],
    );
  }

  /// A bundled icon to upload as the widget's avatar when it has none.
  String? get iconAsset =>
      icon == "chess" ? "assets/data/widget_park_chess.svg" : null;

  Color get tint => switch (icon) {
        "chess" => const Color(0xff3f8f46),
        "draw" => const Color(0xffd0782a),
        "board" => const Color(0xff2d6fc4),
        "paper" => const Color(0xff8a5ad6),
        "play" => const Color(0xffc83a4f),
        _ => const Color(0xff5b3fd1),
      };

  Widget buildIcon({double size = 28}) {
    final asset = iconAsset;
    if (asset != null) {
      return SvgPicture.asset(asset, width: size + 6, height: size + 6);
    }
    return Icon(
        switch (icon) {
          "draw" => Icons.brush_outlined,
          "board" => Icons.co_present_outlined,
          "paper" => Icons.chat_bubble_outline,
          "play" => Icons.smart_display_outlined,
          _ => Icons.widgets_outlined,
        },
        size: size,
        color: Colors.white);
  }
}

class WidgetCatalog {
  static const helpUrl = "https://vommet.app/help/widgets";
  static const browseUrl = "https://vommet.app/widgets/";

  static List<CatalogWidget>? _cache;

  /// The catalog entry for a widget already in a room (same host and path),
  /// for its icon. Null until [load] has run once.
  static CatalogWidget? match(String url) {
    final u = Uri.tryParse(url);
    if (u == null || _cache == null) return null;
    for (final w in _cache!) {
      final c = Uri.tryParse(w.url);
      if (c != null && c.host == u.host && c.path == u.path) return w;
    }
    return null;
  }

  static Future<List<CatalogWidget>> load() async {
    if (_cache != null) return _cache!;
    final text = await rootBundle.loadString("assets/data/widget_catalog.json");
    final json = jsonDecode(text) as Map<String, dynamic>;
    _cache = [
      for (final w in (json["widgets"] as List? ?? []))
        if (w is Map<String, dynamic>) CatalogWidget.fromJson(w),
    ].whereType<CatalogWidget>().toList();
    return _cache!;
  }
}
