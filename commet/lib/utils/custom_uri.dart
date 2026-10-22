import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:commet/config/build_config.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/utils/links/matrix_link.dart';
import 'package:tiamat/config/style/theme_json_converter.dart';

import 'package:commet/utils/register_uri/register_uri.dart';

class CustomURI {
  static StreamController<Uri> _onLinked = StreamController.broadcast();

  static void init() {
    final appLinks = AppLinks();

    appLinks.uriLinkStream.listen((uri) {
      Log.i("Received custom app link: ${uri}");
      _onLinked.add(uri);

      // Vommet (#85): keep a Matrix link that arrives before the main page
      // listens (cold start), so it isn't lost.
      if (MatrixLinkTarget.isMatrixLink(uri)) {
        if (_onMatrixLink.hasListener) {
          _onMatrixLink.add(uri);
        } else {
          _pendingMatrixLink = uri;
        }
      }
    });

    registerAppLinkHandlers();
  }

  static Stream<Uri> get onLinked => _onLinked.stream;

  static final StreamController<Uri> _onMatrixLink =
      StreamController.broadcast();
  static Uri? _pendingMatrixLink;

  /// Matrix links (`matrix:` URIs, `https://matrix.to`) opened from outside
  /// the app, starting with one that arrived before anyone listened.
  static StreamSubscription<Uri> listenMatrixLinks(void Function(Uri) onLink) {
    final subscription = _onMatrixLink.stream.listen(onLink);
    final pending = _pendingMatrixLink;
    _pendingMatrixLink = null;
    if (pending != null) scheduleMicrotask(() => onLink(pending));
    return subscription;
  }

  static CustomURI? parse(String text) {
    Uri? uri;
    try {
      uri = Uri.parse(text);
    } catch (exception) {
      return null;
    }

    if (uri.scheme != BuildConfig.appSchema) {
      return null;
    }

    if (uri.host == "open_room") {
      if ([
        "room_id",
        "client_id"
      ].any((element) => uri!.queryParameters.containsKey(element) == false)) {
        return null;
      }

      return OpenRoomURI(
          roomId: uri.queryParameters["room_id"]!,
          clientId: uri.queryParameters["client_id"]!);
    }

    if (uri.host == "add_widget") {
      var url = uri.queryParameters.tryGet<String>("url");
      var avatar = uri.queryParameters.tryGet<String>("avatar");
      var widgetType = uri.queryParameters.tryGet<String>("type");
      var widgetName = uri.queryParameters.tryGet<String>("name");
      var preview = uri.queryParameters.tryGet<String>("preview");

      if (url != null) {
        return AddWidgetURI(
            widgetUrl: Uri.decodeComponent(url),
            widgetAvatarMxc:
                avatar != null ? Uri.decodeComponent(avatar) : null,
            widgetName:
                widgetName != null ? Uri.decodeComponent(widgetName) : null,
            previewMxc: preview != null && preview.startsWith("mxc") == true
                ? Uri.decodeComponent(preview)
                : null,
            widgetType:
                widgetType != null ? Uri.decodeComponent(widgetType) : null);
      }
    }

    if (uri.host == "accept_call") {
      if ([
        "room_id",
        "client_id",
        "call_id"
      ].any((element) => uri!.queryParameters.containsKey(element) == false)) {
        return null;
      }

      return AcceptCallUri(
          roomId: uri.queryParameters["room_id"]!,
          callId: uri.queryParameters["call_id"]!,
          clientId: uri.queryParameters["client_id"]!);
    }

    if (uri.host == "decline_call") {
      if ([
        "room_id",
        "client_id",
        "call_id"
      ].any((element) => uri!.queryParameters.containsKey(element) == false)) {
        return null;
      }

      return DeclineCallUri(
          roomId: uri.queryParameters["room_id"]!,
          callId: uri.queryParameters["call_id"]!,
          clientId: uri.queryParameters["client_id"]!);
    }

    return null;
  }
}

class OpenRoomURI implements CustomURI {
  final String roomId;
  final String clientId;

  OpenRoomURI({required this.roomId, required this.clientId});

  @override
  String toString() {
    return Uri(
        scheme: BuildConfig.appSchema,
        host: "open_room",
        queryParameters: {"room_id": roomId, "client_id": clientId}).toString();
  }
}

class AddWidgetURI implements CustomURI {
  final String widgetUrl;
  final String? widgetType;
  final String? widgetAvatarMxc;
  final String? widgetName;
  final String? previewMxc;

  AddWidgetURI(
      {required this.widgetUrl,
      this.previewMxc,
      this.widgetName,
      this.widgetType,
      this.widgetAvatarMxc});

  @override
  String toString() {
    return Uri(
        scheme: BuildConfig.appSchema,
        host: "add_widget",
        queryParameters: {
          "url": widgetUrl,
          if (widgetType != null) "type": widgetType,
          if (widgetAvatarMxc != null) "avatar": widgetAvatarMxc!,
        }).toString();
  }
}

class AcceptCallUri implements CustomURI {
  final String roomId;
  final String clientId;
  final String callId;

  AcceptCallUri(
      {required this.roomId, required this.clientId, required this.callId});

  @override
  String toString() {
    return Uri(
        scheme: BuildConfig.appSchema,
        host: "accept_call",
        queryParameters: {
          "room_id": roomId,
          "client_id": clientId,
          "call_id": callId
        }).toString();
  }
}

class DeclineCallUri implements CustomURI {
  final String roomId;
  final String clientId;
  final String callId;

  DeclineCallUri(
      {required this.roomId, required this.clientId, required this.callId});

  @override
  String toString() {
    return Uri(
        scheme: BuildConfig.appSchema,
        host: "decline_call",
        queryParameters: {
          "room_id": roomId,
          "client_id": clientId,
          "call_id": callId
        }).toString();
  }
}

class SsoLoginUri implements CustomURI {
  SsoLoginUri();

  @override
  String toString() {
    return Uri(
        scheme: BuildConfig.appSchema,
        host: "login",
        queryParameters: {}).toString();
  }
}
