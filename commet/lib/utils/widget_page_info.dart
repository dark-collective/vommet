// Vommet: a pasted widget link's own name and icon, read from its page, so a
// custom widget is added as "Watch Together" with its icon rather than as
// its web address with none.
import 'dart:async';
import 'dart:typed_data';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;
import 'package:http/http.dart' as http;

class WidgetPageInfo {
  final String? title;
  final Uri? iconUrl;

  /// The icon's image bytes (PNG, JPEG, GIF or WebP), when it could be fetched.
  final Uint8List? icon;
  final String? iconContentType;

  const WidgetPageInfo(
      {this.title, this.iconUrl, this.icon, this.iconContentType});

  static const maxPageBytes = 512 * 1024;
  static const maxIconBytes = 512 * 1024;

  /// The page's title and preferred icon, from its HTML. Prefers an
  /// apple-touch-icon (a PNG made for this), then a raster "icon". SVG icons
  /// are skipped: the avatar must be an image every client can show.
  static WidgetPageInfo parse(String body, Uri base) {
    final doc = html.parse(body);
    var title = doc.querySelector("title")?.text.trim();
    title = title?.replaceAll(RegExp(r"\s+"), " ");
    if (title != null && title.length > 60) title = title.substring(0, 60);
    if (title != null && title.isEmpty) title = null;

    Uri? icon;
    for (final rel in const ["apple-touch-icon", "icon", "shortcut icon"]) {
      for (final link in doc.querySelectorAll("link[rel]")) {
        if (!_hasRel(link, rel)) continue;
        final href = link.attributes["href"];
        if (href == null || href.isEmpty) continue;
        final type = link.attributes["type"] ?? "";
        if (type.contains("svg") || href.toLowerCase().endsWith(".svg")) {
          continue;
        }
        final u = base.resolve(href);
        if (u.scheme == "https") {
          icon = u;
          break;
        }
      }
      if (icon != null) break;
    }
    return WidgetPageInfo(title: title, iconUrl: icon);
  }

  static bool _hasRel(Element link, String rel) =>
      link.attributes["rel"]!.toLowerCase().trim() == rel ||
      (rel != "shortcut icon" &&
          link.attributes["rel"]!
              .toLowerCase()
              .split(RegExp(r"\s+"))
              .contains(rel));

  /// Fetches the page and its icon. Best effort: anything that fails or
  /// takes too long leaves that field empty.
  static Future<WidgetPageInfo> fetch(Uri page,
      {Duration timeout = const Duration(seconds: 6)}) async {
    final client = http.Client();
    try {
      final res = await client.get(page).timeout(timeout);
      if (res.statusCode != 200 || res.bodyBytes.length > maxPageBytes) {
        return const WidgetPageInfo();
      }
      final info = parse(res.body, page);
      final iconUrl = info.iconUrl;
      if (iconUrl == null) return info;
      try {
        final ir = await client.get(iconUrl).timeout(timeout);
        final ct = (ir.headers["content-type"] ?? "").split(";").first.trim();
        const ok = ["image/png", "image/jpeg", "image/gif", "image/webp"];
        if (ir.statusCode == 200 &&
            ok.contains(ct) &&
            ir.bodyBytes.isNotEmpty &&
            ir.bodyBytes.length <= maxIconBytes) {
          return WidgetPageInfo(
              title: info.title,
              iconUrl: iconUrl,
              icon: ir.bodyBytes,
              iconContentType: ct);
        }
      } catch (_) {}
      return WidgetPageInfo(title: info.title, iconUrl: iconUrl);
    } catch (_) {
      return const WidgetPageInfo();
    } finally {
      client.close();
    }
  }
}
