// Vommet issue 727: open links to well-known services on a privacy-friendly
// frontend the user picked (Invidious for YouTube, Nitter for X, ...), like
// the LibRedirect browser extension. Only links this device opens are
// rewritten: messages, links the user sends and link previews keep the
// original URL, and the Open Link prompt always offers the original.
// Settings › Privacy › Privacy-friendly frontends (AltFrontendsPanel).

import 'dart:math';

import 'package:commet/main.dart';

class AltFrontendService {
  const AltFrontendService({
    required this.id,
    required this.name,
    required this.frontend,
    required this.hosts,
    required this.instances,
    this.subdomainsOf = const [],
    this.rewritePath,
  });

  /// Stored in preferences; never change an existing id.
  final String id;

  /// The service the links go to, e.g. "YouTube".
  final String name;

  /// The frontend the links are opened on, e.g. "Invidious".
  final String frontend;

  /// Exact hosts (lower-case) whose links are rewritten.
  final Set<String> hosts;

  /// Hosts whose every subdomain is rewritten too (e.g. `fandom.com`).
  final List<String> subdomainsOf;

  /// Built-in instances (hosts), the first being the default suggestion.
  /// Taken from LibRedirect's public instance list (2026-10-25).
  final List<String> instances;

  /// Maps the original link to the frontend's path and query; null keeps
  /// both as they are. Returning null from it skips the link.
  final Uri? Function(Uri uri)? rewritePath;

  bool matches(String host) {
    if (hosts.contains(host)) return true;
    return subdomainsOf.any((d) => host.endsWith(".$d"));
  }
}

class AltFrontendRewrite {
  const AltFrontendRewrite(this.service, this.instance, this.uri);

  final AltFrontendService service;

  /// The instance host the link opens on.
  final String instance;

  /// The link on the frontend instance.
  final Uri uri;
}

class AltFrontends {
  static final List<AltFrontendService> services = [
    AltFrontendService(
      id: "youtube",
      name: "YouTube",
      frontend: "Invidious",
      hosts: {
        "youtube.com",
        "www.youtube.com",
        "m.youtube.com",
        "music.youtube.com",
        "youtu.be",
        "youtube-nocookie.com",
        "www.youtube-nocookie.com",
      },
      instances: const [
        "inv.nadeko.net",
        "invidious.nerdvpn.de",
        "yt.chocolatemoo53.com",
        "invidious.tiekoetter.com",
      ],
      rewritePath: _youtubePath,
    ),
    const AltFrontendService(
      id: "twitter",
      name: "X (Twitter)",
      frontend: "Nitter",
      hosts: {
        "x.com",
        "www.x.com",
        "mobile.x.com",
        "twitter.com",
        "www.twitter.com",
        "mobile.twitter.com",
      },
      instances: [
        "xcancel.com",
        "nitter.poast.org",
        "nitter.privacyredirect.com",
        "nitter.tiekoetter.com",
      ],
    ),
    AltFrontendService(
      id: "reddit",
      name: "Reddit",
      frontend: "Redlib",
      hosts: {
        "reddit.com",
        "www.reddit.com",
        "old.reddit.com",
        "new.reddit.com",
        "np.reddit.com",
        "m.reddit.com",
        "redd.it",
      },
      instances: const [
        "safereddit.com",
        "redlib.catsarch.com",
        "redlib.r4fo.com",
        "red.artemislena.eu",
      ],
      rewritePath: _redditPath,
    ),
    AltFrontendService(
      id: "medium",
      name: "Medium",
      frontend: "Scribe",
      hosts: {"medium.com", "www.medium.com"},
      subdomainsOf: const ["medium.com"],
      instances: const [
        "scribe.nixnet.services",
        "scribe.rawbit.ninja",
        "sc.vern.cc",
        "scribe.privacyredirect.com",
      ],
      rewritePath: _mediumPath,
    ),
    const AltFrontendService(
      id: "imgur",
      name: "Imgur",
      frontend: "Rimgo",
      hosts: {"imgur.com", "www.imgur.com", "m.imgur.com", "i.imgur.com"},
      instances: [
        "rimgo.pussthecat.org",
        "imgur.artemislena.eu",
        "rimgo.hostux.net",
        "ri.nadeko.net",
      ],
    ),
    const AltFrontendService(
      id: "tiktok",
      name: "TikTok",
      frontend: "ProxiTok",
      hosts: {"tiktok.com", "www.tiktok.com", "m.tiktok.com"},
      instances: [
        "proxitok.pabloferreiro.es",
        "proxitok.pussthecat.org",
        "tok.artemislena.eu",
        "tok.adminforge.de",
      ],
    ),
    AltFrontendService(
      id: "fandom",
      name: "Fandom",
      frontend: "BreezeWiki",
      hosts: const {},
      subdomainsOf: const ["fandom.com"],
      instances: const [
        "breezewiki.com",
        "antifandom.com",
        "breezewiki.pussthecat.org",
        "breeze.mint.lgbt",
      ],
      rewritePath: _fandomPath,
    ),
    const AltFrontendService(
      id: "genius",
      name: "Genius",
      frontend: "Dumb",
      hosts: {"genius.com", "www.genius.com"},
      instances: [
        "dumb.bloat.cat",
        "dumb.jeikobu.net",
        "dumb.canine.tools",
        "dumb.artemislena.eu",
      ],
    ),
    const AltFrontendService(
      id: "stackoverflow",
      name: "Stack Overflow",
      frontend: "AnonymousOverflow",
      hosts: {"stackoverflow.com", "www.stackoverflow.com"},
      instances: [
        "code.whatever.social",
        "ao.vern.cc",
        "overflow.smnz.de",
        "overflow.adminforge.de",
      ],
    ),
  ];

  static AltFrontendService? serviceById(String id) {
    for (final s in services) {
      if (s.id == id) return s;
    }
    return null;
  }

  static AltFrontendService? serviceFor(Uri uri) {
    if (uri.scheme != "http" && uri.scheme != "https") return null;
    final host = uri.host.toLowerCase();
    if (host.isEmpty) return null;
    for (final s in services) {
      if (s.matches(host)) return s;
    }
    return null;
  }

  static bool get enabled => preferences.altFrontendsEnabled.value;

  static bool isServiceOn(AltFrontendService service) =>
      preferences.altFrontendsServices.value.contains(service.id);

  /// Preferences store instances as "<service id>=<host>".
  static List<String> _hostsIn(List<String> entries, String serviceId) => [
        for (final e in entries)
          if (e.startsWith("$serviceId=")) e.substring(serviceId.length + 1)
      ];

  /// The instances picked for [service]; one is chosen at random per link.
  static List<String> selectedInstances(AltFrontendService service) =>
      _hostsIn(preferences.altFrontendsInstances.value, service.id);

  /// Instances the user added for [service].
  static List<String> customInstances(AltFrontendService service) =>
      _hostsIn(preferences.altFrontendsCustomInstances.value, service.id);

  /// Built-in and user-added instances for [service], without duplicates.
  static List<String> allInstances(AltFrontendService service) => {
        ...service.instances,
        ...customInstances(service),
      }.toList();

  static Future<void> setSelectedInstances(
      AltFrontendService service, List<String> hosts) async {
    final others = preferences.altFrontendsInstances.value
        .where((e) => !e.startsWith("${service.id}="));
    await preferences.altFrontendsInstances
        .set([...others, for (final h in hosts) "${service.id}=$h"]);
  }

  static Future<void> setServiceOn(AltFrontendService service, bool on) async {
    final ids = preferences.altFrontendsServices.value
        .where((id) => id != service.id)
        .toList();
    if (on) ids.add(service.id);
    await preferences.altFrontendsServices.set(ids);
  }

  /// The host of a user-entered instance ("https://inv.example.org/" or
  /// "inv.example.org"), or null when it isn't one.
  static String? normalizeInstance(String input) {
    var text = input.trim();
    if (text.isEmpty) return null;
    if (!text.contains("://")) text = "https://$text";
    final uri = Uri.tryParse(text);
    if (uri == null || (uri.scheme != "https" && uri.scheme != "http")) {
      return null;
    }
    final host = uri.host.toLowerCase();
    if (host.isEmpty || !host.contains(".")) return null;
    return uri.hasPort ? "$host:${uri.port}" : host;
  }

  static Future<void> addCustomInstance(
      AltFrontendService service, String host) async {
    final entry = "${service.id}=$host";
    final list = preferences.altFrontendsCustomInstances.value;
    if (list.contains(entry)) return;
    await preferences.altFrontendsCustomInstances.set([...list, entry]);
  }

  static Future<void> removeCustomInstance(
      AltFrontendService service, String host) async {
    await preferences.altFrontendsCustomInstances.set(preferences
        .altFrontendsCustomInstances.value
        .where((e) => e != "${service.id}=$host")
        .toList());
    await setSelectedInstances(
        service, selectedInstances(service).where((h) => h != host).toList());
  }

  /// The service whose frontend [uri] would open on, or null.
  static AltFrontendService? activeServiceFor(Uri uri) {
    if (!enabled) return null;
    final service = serviceFor(uri);
    if (service == null || !isServiceOn(service)) return null;
    if (selectedInstances(service).isEmpty) return null;
    return service;
  }

  /// Where this device opens [uri], or null to open it as it is (the
  /// setting or the service is off, no instance is picked, or the link
  /// isn't one the frontend can show).
  static AltFrontendRewrite? rewrite(Uri uri, {Random? random}) {
    final service = activeServiceFor(uri);
    if (service == null) return null;
    final instances = selectedInstances(service);
    final instance = instances.length == 1
        ? instances.first
        : instances[(random ?? Random()).nextInt(instances.length)];
    final rewritten = rewriteWith(service, uri, instance);
    return rewritten == null
        ? null
        : AltFrontendRewrite(service, instance, rewritten);
  }

  /// [uri] on [instance] of [service]'s frontend; null when it can't be.
  static Uri? rewriteWith(
      AltFrontendService service, Uri uri, String instance) {
    final mapped =
        service.rewritePath == null ? uri : service.rewritePath!(uri);
    if (mapped == null) return null;
    final base = Uri.parse("https://$instance");
    return Uri(
      scheme: base.scheme,
      host: base.host,
      port: base.hasPort ? base.port : null,
      path: mapped.path.isEmpty ? "/" : mapped.path,
      query: mapped.hasQuery ? mapped.query : null,
      fragment: mapped.hasFragment ? mapped.fragment : null,
    );
  }

  /// youtu.be/<id>?t=1 → /watch?v=<id>&t=1; other paths stay as they are.
  static Uri? _youtubePath(Uri uri) {
    if (uri.host.toLowerCase() != "youtu.be") return uri;
    final id = uri.pathSegments.isEmpty ? "" : uri.pathSegments.first;
    if (id.isEmpty) return null;
    return Uri(
      path: "/watch",
      queryParameters: {"v": id, ...uri.queryParameters},
      fragment: uri.hasFragment ? uri.fragment : null,
    );
  }

  /// redd.it/<id> → /comments/<id>; image and video hosts aren't matched.
  static Uri? _redditPath(Uri uri) {
    if (uri.host.toLowerCase() != "redd.it") return uri;
    final id = uri.pathSegments.isEmpty ? "" : uri.pathSegments.first;
    if (id.isEmpty) return null;
    return Uri(path: "/comments/$id");
  }

  /// <user>.medium.com/<post> → /@<user>/<post> (Scribe reads the post id
  /// from the last path segment either way).
  static Uri? _mediumPath(Uri uri) {
    final host = uri.host.toLowerCase();
    if (host == "medium.com" || host == "www.medium.com") return uri;
    final user = host.substring(0, host.length - ".medium.com".length);
    return uri.replace(path: "/@$user${uri.path}");
  }

  /// <wiki>.fandom.com/wiki/<page> → /<wiki>/wiki/<page>.
  static Uri? _fandomPath(Uri uri) {
    final host = uri.host.toLowerCase();
    final wiki = host.substring(0, host.length - ".fandom.com".length);
    if (wiki.isEmpty || wiki == "www" || wiki.contains(".")) return null;
    return uri.replace(path: "/$wiki${uri.path}");
  }
}
