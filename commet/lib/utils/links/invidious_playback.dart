// Vommet issue 175: YouTube links play inside Vommet through the Invidious
// instance picked for YouTube in Settings › Privacy › Privacy-friendly
// frontends (Vommet issue 727). The link preview shows the video in the
// usual player; nothing is loaded until play is pressed, and only from the
// instance (`local=true` makes it proxy the stream, so YouTube's servers
// are never contacted by the app).

import 'dart:math';

import 'package:commet/cache/file_provider.dart';
import 'package:commet/client/attachment.dart';
import 'package:commet/main.dart';
import 'package:commet/utils/links/alt_frontends.dart';
import 'package:flutter/widgets.dart';

class InvidiousVideo {
  const InvidiousVideo(
      {required this.id,
      required this.instance,
      required this.stream,
      this.portrait = false});

  /// The YouTube video id.
  final String id;

  /// The Invidious instance host it plays from.
  final String instance;

  /// A muxed MP4 stream proxied by the instance.
  final Uri stream;

  /// A Short: shown in a portrait frame.
  final bool portrait;

  VideoAttachment attachment({ImageProvider? thumbnail}) => VideoAttachment(
        WebFileProvider(stream),
        mimeType: "video/mp4",
        streamUrl: stream,
        thumbnail: thumbnail,
        width: portrait ? 720 : 1280,
        height: portrait ? 1280 : 720,
      );
}

class InvidiousPlayback {
  static final RegExp _videoId = RegExp(r"^[A-Za-z0-9_-]{11}$");

  static AltFrontendService get _youtube =>
      AltFrontends.serviceById("youtube")!;

  /// Whether YouTube links play inside Vommet: the frontends setting, its
  /// YouTube switch with an instance, and "Play videos inside Vommet".
  static bool get enabled =>
      preferences.altFrontendsYoutubePlayback.value &&
      AltFrontends.enabled &&
      AltFrontends.isServiceOn(_youtube) &&
      AltFrontends.selectedInstances(_youtube).isNotEmpty;

  /// The video id of a YouTube video link, and whether it is a Short.
  static (String, bool)? parse(Uri uri) {
    if (uri.scheme != "http" && uri.scheme != "https") return null;
    final host = uri.host.toLowerCase();
    if (!_youtube.matches(host)) return null;
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    String? id;
    var portrait = false;
    if (host == "youtu.be") {
      id = segments.isEmpty ? null : segments.first;
    } else if (segments.length == 1 && segments.first == "watch") {
      id = uri.queryParameters["v"];
    } else if (segments.length >= 2 &&
        const ["shorts", "live", "embed", "v"].contains(segments.first)) {
      id = segments[1];
      portrait = segments.first == "shorts";
    }
    if (id == null || !_videoId.hasMatch(id)) return null;
    return (id, portrait);
  }

  /// The video [uri] links to, played from one of the picked instances, or
  /// null when playback is off or [uri] isn't a YouTube video.
  static InvidiousVideo? videoFor(Uri uri, {Random? random}) {
    if (!enabled) return null;
    final parsed = parse(uri);
    if (parsed == null) return null;
    final instances = AltFrontends.selectedInstances(_youtube);
    final instance = instances.length == 1
        ? instances.first
        : instances[(random ?? Random()).nextInt(instances.length)];
    final base = Uri.parse("https://$instance");
    final stream = Uri(
        scheme: "https",
        host: base.host,
        port: base.hasPort ? base.port : null,
        path: "/latest_version",
        queryParameters: {"id": parsed.$1, "itag": "18", "local": "true"});
    return InvidiousVideo(
        id: parsed.$1, instance: instance, stream: stream, portrait: parsed.$2);
  }

  /// Whether [host] is a picked YouTube instance: its streams play without
  /// the "Stream Remote Video" prompt, since the user chose it.
  static bool isPickedInstance(String host) {
    if (!enabled) return false;
    final h = host.toLowerCase();
    return AltFrontends.selectedInstances(_youtube)
        .any((i) => i == h || i.split(":").first == h);
  }
}
