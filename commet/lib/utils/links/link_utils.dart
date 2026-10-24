import 'package:commet/debug/log.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/utils/error_utils.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:commet/utils/links/matrix_link.dart';
import 'package:commet/utils/links/smart_link_handler.dart';
import 'package:commet/utils/links/tracking_parameters_cleaner.dart';
import 'package:commet/utils/links/trusted_link_domains.dart';

import 'package:flutter/widgets.dart';
import 'package:url_launcher/url_launcher.dart';

class LinkUtils {
  static Future<void> open(Uri uri,
      {String? clientId,
      String? contextRoomId,
      BuildContext? context,
      bool bypassConfirmation = false,
      bool filterTrackingParameters = true}) async {
    if (context != null) {
      ErrorUtils.tryRun(context, () async {
        await _open(uri,
            clientId: clientId,
            context: context,
            contextRoomId: contextRoomId,
            bypassConfirmation: bypassConfirmation,
            filterTrackingParameters: filterTrackingParameters);
      });
    } else {
      await _open(uri,
          clientId: clientId,
          context: context,
          contextRoomId: contextRoomId,
          bypassConfirmation: bypassConfirmation,
          filterTrackingParameters: filterTrackingParameters);
    }
  }

  static Future<void> _open(Uri uri,
      {String? clientId,
      String? contextRoomId,
      BuildContext? context,
      bool bypassConfirmation = false,
      bool filterTrackingParameters = true}) async {
    if (uri.host == "matrix.to") {
      // Vommet issue 665: the link's event id and every `via` are kept. The
      // event id used to stay glued to the room id ("!room/$event"), which
      // matched no room, so a link to a message in a room you're in offered
      // to join it.
      MatrixLinkTarget? target;
      try {
        target = MatrixLinkTarget.parse(uri);
      } on FormatException {
        target = null;
      }

      if (target != null && clientId != null) {
        switch (target.kind) {
          case MatrixLinkKind.user:
            return EventBus.openUserProfile
                .add((target.identifier, clientId, contextRoomId));
          case MatrixLinkKind.room:
          case MatrixLinkKind.roomAlias:
            return EventBus.doOpenRoom(target.roomAddress,
                clientId: clientId, eventId: target.eventId);
        }
      }
    }

    // Vommet: e-mail addresses in messages link as mailto:; hand them to
    // the mail app.
    if (uri.scheme == "mailto") {
      launchUrl(uri, mode: LaunchMode.externalApplication);
      return;
    }

    if (!(uri.scheme == "http" || uri.scheme == "https")) {
      return;
    }

    var openUrl = uri;

    if (context != null) {
      var handler = await SmartLinkHandling.getHandler(openUrl);

      if (handler != null) {
        for (var executor in handler.executors) {
          if (await executor.canHandleLink(uri)) {
            var confirm = await AdaptiveDialog.confirmation(context,
                prompt: executor.getDescription(uri),
                title: "Open in ${handler.appName}?");

            if (confirm == true) {
              executor.execute(openUrl);
            }

            if (confirm == false) {
              launchUrl(openUrl, mode: LaunchMode.externalApplication);
            }

            return;
          }
        }
      }
    }

    var cleanedUrl = filterTrackingParameters
        ? await UrlTrackingParametersCleaner.cleanTrackingParameters(uri)
        : uri;

    // Vommet issue 503: links to a trusted domain open without asking, with
    // trackers still removed; the prompts below offer to trust the domain.
    if (TrustedLinkDomains.isTrusted(uri)) {
      bypassConfirmation = true;
    }
    final domain = TrustedLinkDomains.domainOf(uri);
    var trustDomain = false;
    Widget Function(BuildContext)? trustSwitch = domain == null
        ? null
        : (context) => TrustLinkDomainSwitch(
            domain: domain, onChanged: (value) => trustDomain = value);

    if (cleanedUrl.toString() != uri.toString()) {
      if (context != null) {
        if (!bypassConfirmation) {
          var confirm = await AdaptiveDialog.confirmation(context,
              title: "Open Link",
              confirmationText: "Open",
              cancelText: "Open Original Link",
              customBuilder: trustSwitch,
              prompt:
                  "This link contained trackers, which have been removed. Open `$cleanedUrl` in your browser?");

          if (confirm == null) return;

          if (trustDomain) await TrustedLinkDomains.trust(uri);

          if (confirm == true) {
            openUrl = cleanedUrl;
          }
        } else {
          openUrl = cleanedUrl;
        }
      }
    } else {
      if (!bypassConfirmation) {
        if (context != null) {
          if (await AdaptiveDialog.confirmation(context,
                  title: "Open Link",
                  confirmationText: "Open",
                  cancelText: "Cancel",
                  customBuilder: trustSwitch,
                  prompt: "Open `$uri` in your web browser?") !=
              true) {
            return;
          }

          if (trustDomain) await TrustedLinkDomains.trust(uri);
        }
      }
    }

    Log.d("Opening Link: $openUrl");

    launchUrl(openUrl, mode: LaunchMode.externalApplication);
  }
}
