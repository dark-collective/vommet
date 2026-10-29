import 'package:commet/client/components/push_notification/linux/linux_notification_markup.dart';
import 'package:commet/client/components/push_notification/linux/linux_notifier.dart';
import 'package:commet/client/components/push_notification/modifiers/notification_modifiers.dart';
import 'package:commet/client/components/push_notification/notification_content.dart';
import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/client/components/push_notification/notification_manager.dart';
import 'package:commet/client/components/url_preview/url_preview_component.dart';
import 'package:commet/client/components/url_preview/url_preview_suppression.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/matrix_mxc_image_provider.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/client/room.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/atoms/rich_text/matrix_html_parser.dart';
import 'package:commet/utils/image/lod_image.dart';
import 'package:commet/utils/image_utils.dart';
import 'package:commet/utils/private_files/private_media_files.dart';
import 'package:commet/debug/log.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:html/dom.dart' as html;
import 'package:html/parser.dart';
import 'package:markdown/markdown.dart';
import 'package:vector_math/vector_math.dart';
import 'dart:ui' as ui;

class NotificationModifierLinuxFormatting implements NotificationModifier {
  final double thumbnailImageSize = 100;

  @override
  Future<NotificationContent?> process(NotificationContent content,
      {Function(String reason)? onNotificationRejected}) async {
    if (preferences.formatNotificationBody.value == false) {
      return content;
    }

    // Vommet: a daemon without "body-markup" shows the body as plain text,
    // so formatting would only show up as raw tags.
    final notifier = NotificationManager.notifier;
    if (notifier is LinuxNotifier && notifier.bodyMarkup == false) {
      return content;
    }

    if (content is MessageNotificationContent &&
        content.formattedContent != null &&
        content.formatType != null) {
      final client = clientManager!.getClient(content.clientId);
      final room = client!.getRoom(content.roomId)!;

      var formattedContent = await convertFormattedContent(
        content.formattedContent!,
        content.formatType!,
        room,
        // Vommet issue 352: content is the plain body, which keeps <url>.
        suppression: UrlPreviewSuppression(content.content),
      );

      final bool showImages =
          room.shouldPreviewMedia && preferences.showMediaInNotifications.value;

      if (showImages && content.attachedImage != null) {
        final uri = await prepareImageForInline(
          content.attachedImage!,
          thumbnailImageSize,
        );
        if (uri != null) {
          formattedContent = (formattedContent ?? "") +
              '\n<img src="${LinuxNotificationMarkup.attribute(uri.toString())}"/>';
        }
      }

      if (formattedContent != null) {
        content.content = formattedContent;
        content.contentIsMarkup = true;
      }
    }

    return content;
  }

  Future<String?> convertFormattedContent(
    String formattedContent,
    String format,
    Room room, {
    UrlPreviewSuppression? suppression,
  }) async {
    if (format == "org.matrix.custom.html" && room is MatrixRoom) {
      return convertMatrixHtml(formattedContent, room,
          suppression: suppression);
    }

    if (format == "chat.commet.custom.matrix_plain") {
      return convertPlainText(formattedContent, room, suppression: suppression);
    }

    return null;
  }

  Future<String?> convertMatrixHtml(String formattedContent, Room room,
      {UrlPreviewSuppression? suppression}) async {
    final parser = HtmlParser(formattedContent);
    final document = parser.parse();

    bool bigEmoji = shouldDoBigEmoji(document);

    String result = "";

    final bool showImages =
        room.shouldPreviewMedia && preferences.showMediaInNotifications.value;

    for (var node in document.nodes) {
      result += await handleMatrixNode(
        node,
        room as MatrixRoom,
        emojiSize: bigEmoji ? 32 : 16,
        showImages: showImages,
        suppression: suppression,
      );
    }

    return result;
  }

  Future<String> handleMatrixNode(
    html.Node node,
    MatrixRoom room, {
    required double emojiSize,
    required bool showImages,
    UrlPreviewSuppression? suppression,
  }) async {
    String content = "";

    if (node is html.Element) {
      if (node.localName == "img") {
        return await handleMatrixImage(
          node,
          showImages,
          emojiSize,
          room,
          content,
        );
      }

      if (node.localName == "mx-reply") {
        return "";
      }

      if (node.localName == "a") {
        return await handleMatrixLinks(node, room, suppression: suppression);
      }

      String tag = switch (node.localName!) {
        "em" => "i",
        "b" => "b",
        "strong" => "b",
        "i" => "i",
        "img" => "img",
        "pre" => "i",
        "code" => "i",
        _ => "",
      };

      if (tag != "") {
        content += "<$tag>";

        for (var child in node.nodes) {
          content += await handleMatrixNode(
            child,
            room,
            emojiSize: emojiSize,
            showImages: showImages,
            suppression: suppression,
          );
        }

        content += "</$tag>";
      } else {
        for (var child in node.nodes) {
          content += await handleMatrixNode(
            child,
            room,
            emojiSize: emojiSize,
            showImages: showImages,
            suppression: suppression,
          );
        }
      }
    } else {
      if (node is html.Text) {
        // Vommet: the parser has decoded entities, so "&lt;b&gt;" is "<b>"
        // again here and must be escaped before it goes into the markup.
        content += LinuxNotificationMarkup.text(node.text);
      }
    }

    return content;
  }

  Future<String> handleMatrixLinks(html.Element node, MatrixRoom room,
      {UrlPreviewSuppression? suppression}) async {
    final url = node.attributes["href"];
    if (url == null) return "";

    var uri = Uri.parse(url);

    if (!(uri.scheme == "https" || uri.scheme == "https")) {
      return "";
    }

    final preview = room.client.getComponent<UrlPreviewComponent>();

    bool shouldGetPreview = preview?.shouldGetPreviewsInRoom(room) == true &&
        preferences.previewUrlInNotifications.value &&
        suppression?.allowsPreview(uri) != false;

    if (!shouldGetPreview) {
      return _plainLink(uri);
    }

    var prev = await preview!.getPreviewForUrl(room, uri);

    bool useUserText = node.text.trim() != "" && node.text != url;
    final href = LinuxNotificationMarkup.attribute(uri.toString());

    if (prev?.title != null) {
      var title = prev!.title!;
      const maxLength = 50;
      if (title.length > maxLength) {
        title = title.substring(0, maxLength) + "...";
      }

      String result =
          '<a href="$href"> ${useUserText ? LinuxNotificationMarkup.text(node.text) : ""} <i>"${LinuxNotificationMarkup.text(title)}"</i> <i>(${LinuxNotificationMarkup.text(uri.authority)})</i>';

      if (prev.image != null &&
          room.shouldPreviewMedia &&
          preferences.showMediaInNotifications.value) {
        Uri? imagePath = await prepareImageForInline(
          prev.image!,
          thumbnailImageSize,
        );

        if (imagePath != null) {
          result +=
              '\n<img src="${LinuxNotificationMarkup.attribute(imagePath.toString())}"/>';
        }
      }

      result += "</a>";
      return result;
    }

    return _plainLink(uri);
  }

  String _plainLink(Uri uri) =>
      '<a href="${LinuxNotificationMarkup.attribute(uri.toString())}">'
      '${LinuxNotificationMarkup.text(uri.toString())}</a>';

  Future<String> handleMatrixImage(
    html.Element node,
    bool showImages,
    double emojiSize,
    MatrixRoom room,
    String content,
  ) async {
    final src = node.attributes["src"];
    final alt = node.attributes["alt"];

    LinuxServerCapabilities? capabilities;
    if (NotificationManager.notifier is LinuxNotifier) {
      capabilities =
          (NotificationManager.notifier as LinuxNotifier).capabilities;
    }

    if (capabilities?.bodyImages != true || showImages == false) {
      return "<i>${LinuxNotificationMarkup.text(alt)}</i>";
    }

    if (src != null && src.startsWith("mxc://")) {
      var img = MatrixMxcImage(
        Uri.parse(src),
        (room.client as MatrixClient).matrixClient,
        doFullres: true,
        doThumbnail: false,
        sensitive: room.isE2EE,
      );

      final path = await prepareImageForInline(img, emojiSize);
      if (path == null) return "<i>${LinuxNotificationMarkup.text(alt)}</i>";

      String result =
          '<img src="${LinuxNotificationMarkup.attribute(path.toString())}" ';

      if (alt != null) {
        result += 'alt="${LinuxNotificationMarkup.attribute(alt)}"';
      }

      result += "/>";

      return result;
    }
    return content;
  }

  /// Vommet: the longest a notification's image file is kept. The notifier
  /// deletes it sooner, once the notification is closed (see
  /// [LinuxNotifier.trackNotificationFiles]); this covers a notification
  /// that was never shown and a daemon that keeps notifications forever.
  static const Duration inlineImageLifetime = Duration(hours: 1);

  /// [image] scaled to [maxSize] high, as a PNG the notification daemon can
  /// read by path.
  ///
  /// Vommet: the image can come from an encrypted message (or a link in
  /// one), so it goes to a private copy (0600, random name, in the app's own
  /// media_open folder), never into the file cache, and no event id or URL
  /// is part of any name. Null when no private copy can be made.
  Future<Uri?> prepareImageForInline(
    ImageProvider image,
    double maxSize,
  ) async {
    if (image case LODImageProvider _) {
      await image.fetchFullRes();
    }

    var i = await ImageUtils.imageProviderToImage(image);

    var recorder = ui.PictureRecorder();
    Canvas c = Canvas(recorder);

    var sizeVector = Vector2(i.width.toDouble(), i.height.toDouble());
    sizeVector.normalize();

    sizeVector = sizeVector * (maxSize / sizeVector.y);

    var size = Size(sizeVector.x, sizeVector.y);
    var center = Offset(size.width / 2, size.height / 2);

    c.drawImageRect(
      i,
      Rect.fromLTWH(0, 0, i.width.toDouble(), i.height.toDouble()),
      Rect.fromCenter(center: center, width: size.width, height: size.height),
      Paint()..filterQuality = FilterQuality.medium,
    );

    var pic = recorder.endRecording();

    var resized = await pic.toImage(size.width.round(), size.height.round());

    var resultBytes = await resized.toByteData(format: ui.ImageByteFormat.png);
    if (resultBytes == null) return null;

    try {
      final uri = await PrivateMediaFiles.write(
          resultBytes.buffer.asUint8List(),
          extension: "png");
      PrivateMediaFiles.releaseAfter(
          Future<void>.delayed(inlineImageLifetime), uri);
      return uri;
    } catch (error) {
      Log.w("Couldn't make a private notification image: $error");
      return null;
    }
  }

  Future<String?> convertPlainText(String formattedContent, Room room,
      {UrlPreviewSuppression? suppression}) async {
    final html = markdownToHtml(formattedContent,
        extensionSet: ExtensionSet(
          [],
          [AutolinkExtensionSyntax()],
        ));
    return convertMatrixHtml(html, room, suppression: suppression);
  }
}
