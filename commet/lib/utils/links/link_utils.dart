import 'package:commet/debug/log.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/pages/settings/categories/room/emoji_packs/import_destinations.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/utils/error_utils.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:commet/utils/links/alt_frontends.dart';
import 'package:commet/utils/links/alt_frontends_ui.dart';
import 'package:commet/utils/links/matrix_link.dart';
import 'package:commet/utils/links/smart_link_handler.dart';
import 'package:commet/utils/links/tracking_parameters_cleaner.dart';
import 'package:commet/utils/links/trusted_link_domains.dart';
import 'package:commet/utils/sticker_pack_links.dart';

import 'package:flutter/widgets.dart';
import 'package:url_launcher/url_launcher.dart';

class LinkUtils {
  static Future<void> open(Uri uri,
      {String? clientId,
      String? contextRoomId,
      BuildContext? context,
      bool bypassConfirmation = false,
      bool filterTrackingParameters = true,
      bool useAltFrontends = true}) async {
    if (context != null) {
      ErrorUtils.tryRun(context, () async {
        await _open(uri,
            clientId: clientId,
            context: context,
            contextRoomId: contextRoomId,
            bypassConfirmation: bypassConfirmation,
            filterTrackingParameters: filterTrackingParameters,
            useAltFrontends: useAltFrontends);
      });
    } else {
      await _open(uri,
          clientId: clientId,
          context: context,
          contextRoomId: contextRoomId,
          bypassConfirmation: bypassConfirmation,
          filterTrackingParameters: filterTrackingParameters,
          useAltFrontends: useAltFrontends);
    }
  }

  static Future<void> _open(Uri uri,
      {String? clientId,
      String? contextRoomId,
      BuildContext? context,
      bool bypassConfirmation = false,
      bool filterTrackingParameters = true,
      bool useAltFrontends = true}) async {
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

    // Vommet issue 18: a Telegram/Signal sticker pack link offers the pack
    // import dialog; "Open link" opens it as usual, without a second prompt.
    if (context != null &&
        StickerPackLinkList.importableLinks(uri.toString()) != null) {
      final importPack = await AdaptiveDialog.confirmation(context,
          title: EmoticonImportDestinations.titleImportStickerLink,
          prompt: EmoticonImportDestinations.promptImportStickerLink,
          confirmationText:
              EmoticonImportDestinations.promptImportStickerLinkImport,
          cancelText: EmoticonImportDestinations.promptImportStickerLinkOpen);
      if (importPack == null || !context.mounted) return;
      if (importPack) {
        final client =
            clientId == null ? null : clientManager?.getClient(clientId);
        final room =
            contextRoomId == null ? null : client?.getRoom(contextRoomId);
        if (await EmoticonImportDestinations.showForLinks(
            context, uri.toString(),
            client: client, room: room)) {
          return;
        }
      }
      bypassConfirmation = true;
    }

    // Vommet issue 727: a link to a service whose privacy-friendly frontend
    // is turned on opens there (trackers removed too); the prompt offers
    // the original link instead.
    final frontend = useAltFrontends ? AltFrontends.rewrite(uri) : null;
    if (frontend != null) {
      final original = filterTrackingParameters
          ? await UrlTrackingParametersCleaner.cleanTrackingParameters(uri)
          : uri;
      final target = AltFrontends.rewriteWith(
              frontend.service, original, frontend.instance) ??
          frontend.uri;
      return _openOnFrontend(original, target, frontend,
          context: context, bypassConfirmation: bypassConfirmation);
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

  static Future<void> _openOnFrontend(
      Uri original, Uri target, AltFrontendRewrite frontend,
      {BuildContext? context, bool bypassConfirmation = false}) async {
    var openUrl = target;

    // Trusting the original domain (or the instance) skips the prompt.
    if (TrustedLinkDomains.isTrusted(original) ||
        TrustedLinkDomains.isTrusted(target)) {
      bypassConfirmation = true;
    }

    if (context != null && !bypassConfirmation) {
      final domain = TrustedLinkDomains.domainOf(original);
      var trustDomain = false;
      final confirm = await AdaptiveDialog.confirmation(context,
          title: altFrontendOpenTitle(frontend.service.frontend),
          confirmationText: altFrontendOpenButton(frontend.service.frontend),
          cancelText: altFrontendOpenOriginal,
          customBuilder: domain == null
              ? null
              : (context) => TrustLinkDomainSwitch(
                  domain: domain, onChanged: (value) => trustDomain = value),
          prompt: altFrontendOpenPrompt(
              frontend.service.name, frontend.instance, target.toString()));

      if (confirm == null) return;
      if (trustDomain) await TrustedLinkDomains.trust(original);
      if (confirm == false) openUrl = original;
    }

    Log.d("Opening Link: $openUrl");

    launchUrl(openUrl, mode: LaunchMode.externalApplication);
  }
}
