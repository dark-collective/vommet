import 'package:commet/client/client.dart';
import 'package:commet/client/components/widgets/widget_component.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/matrix_mxc_image_provider.dart';
import 'package:commet/ui/organisms/room_widgets/widget_catalog.dart';
import 'package:commet/utils/custom_uri.dart';
import 'package:commet/utils/error_utils.dart';
import 'package:commet/utils/widget_page_info.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:tiamat/tiamat.dart' as tiamat;

class AddWidgetDialog extends StatefulWidget {
  const AddWidgetDialog({
    super.key,
    required this.widgetUri,
    required this.room,
    this.iconAsset,
    this.pageIcon,
  });

  final AddWidgetURI widgetUri;
  final Room room;

  /// Vommet: a bundled SVG icon (from the widget picker), uploaded as the
  /// widget's avatar when it's added.
  final String? iconAsset;

  /// Vommet: the icon read from a pasted link's page, uploaded as the
  /// widget's avatar when it's added (not before, so cancelling leaves
  /// nothing behind).
  final WidgetPageInfo? pageIcon;

  @override
  State<AddWidgetDialog> createState() => _AddWidgetDialogState();
}

class _AddWidgetDialogState extends State<AddWidgetDialog> {
  bool addingWidget = false;

  /// Vommet: the catalog entry for this widget, for its servers and notes.
  CatalogWidget? catalog;

  @override
  void initState() {
    super.initState();
    WidgetCatalog.load().then((_) {
      if (mounted) {
        setState(
            () => catalog = WidgetCatalog.match(widget.widgetUri.widgetUrl));
      }
    });
  }

  /// Vommet: a widget link can ask for values made fresh for this room when
  /// it's added: `$vommet.new_id` (Drawpile's session ID alias) and
  /// `$vommet.new_secret` (its password).
  static String fillNewValues(String url) {
    const chars = "abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789";
    final rnd = Random.secure();
    String make(int n) => String.fromCharCodes(Iterable.generate(
        n, (_) => chars.codeUnitAt(rnd.nextInt(chars.length))));
    return url
        .replaceAll("\$vommet.new_id", make(12))
        .replaceAll("\$vommet.new_secret", make(20));
  }

  Widget buildServers(CatalogWidget c, ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 6,
      children: [
        tiamat.Text.label("Canvas server"),
        for (final (i, s) in c.servers.indexed)
          Opacity(
            opacity: s.later ? 0.5 : 1,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: i == 0
                    ? scheme.primary.withAlpha(24)
                    : scheme.surfaceContainer,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: i == 0 ? scheme.primary : Colors.transparent,
                    width: 1.4),
              ),
              child: Row(spacing: 10, children: [
                Icon(
                    i == 0
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    size: 20,
                    color: i == 0 ? scheme.primary : scheme.onSurfaceVariant),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(spacing: 6, children: [
                          Flexible(child: tiamat.Text.label(s.name)),
                          if (s.later)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                  color: scheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(6)),
                              child: Text("Coming later",
                                  style: TextStyle(
                                      color: scheme.onSurfaceVariant,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700)),
                            ),
                        ]),
                        tiamat.Text.labelLow(s.detail),
                      ]),
                ),
              ]),
            ),
          ),
      ],
    );
  }

  Widget buildNotices(CatalogWidget c, ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: scheme.surfaceContainer,
          borderRadius: BorderRadius.circular(12)),
      child: Column(spacing: 8, children: [
        for (final n in c.notices)
          Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 8,
              children: [
                Icon(n.iconData, size: 18, color: scheme.onSurfaceVariant),
                Expanded(child: tiamat.Text.labelLow(n.text)),
              ]),
      ]),
    );
  }

  /// Vommet: renders the bundled SVG on a rounded tile and uploads it as a
  /// PNG. Best effort: the widget is still added without an icon on failure.
  Future<Uri?> uploadIcon(String asset) async {
    final client = widget.room.client;
    if (client is! MatrixClient) return null;
    try {
      const size = 256.0;
      final info = await vg.loadPicture(SvgAssetLoader(asset), null);
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              const Rect.fromLTWH(0, 0, size, size), const Radius.circular(56)),
          Paint()..color = const Color(0xff3f8f46));
      final scale = size * 0.78 / info.size.longestSide;
      canvas.translate((size - info.size.width * scale) / 2,
          (size - info.size.height * scale) / 2);
      canvas.scale(scale);
      canvas.drawPicture(info.picture);
      info.picture.dispose();
      final image =
          await recorder.endRecording().toImage(size.toInt(), size.toInt());
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (png == null) return null;
      return await client.matrixClient.uploadContent(png.buffer.asUint8List(),
          filename: "widget-icon.png", contentType: "image/png");
    } catch (_) {
      return null;
    }
  }

  /// Vommet: uploads the icon read from the widget's page. Best effort.
  Future<Uri?> uploadPageIcon(WidgetPageInfo info) async {
    final client = widget.room.client;
    if (client is! MatrixClient || info.icon == null) return null;
    try {
      final ext = (info.iconContentType ?? "image/png").split("/").last;
      return await client.matrixClient.uploadContent(info.icon!,
          filename: "widget-icon.$ext", contentType: info.iconContentType);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    var uri = Uri.parse(widget.widgetUri.widgetUrl);
    return SizedBox(
      width: 500,
      child: Column(
        spacing: 8,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(4.0),
            child: Row(
              spacing: 8,
              children: [
                if (widget.widgetUri.widgetAvatarMxc == null &&
                    widget.pageIcon?.icon != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(7),
                    child: Image.memory(widget.pageIcon!.icon!,
                        width: 30, height: 30, fit: BoxFit.cover),
                  ),
                if (widget.widgetUri.widgetAvatarMxc == null &&
                    widget.pageIcon?.icon == null &&
                    widget.iconAsset != null)
                  SvgPicture.asset(widget.iconAsset!, width: 30, height: 30),
                if (widget.widgetUri.widgetAvatarMxc != null)
                  SizedBox(
                    width: 30,
                    height: 30,
                    child: Image(
                        fit: BoxFit.cover,
                        image: MatrixMxcImage(
                            Uri.parse(widget.widgetUri.widgetAvatarMxc!),
                            doThumbnail: false,
                            doFullres: true,
                            (widget.room.client as MatrixClient).matrixClient)),
                  ),
                tiamat.Text.label(
                    "Add the widget '${widget.widgetUri.widgetName ?? "Custom"}' to ${widget.room.displayName}?"),
              ],
            ),
          ),
          tiamat.Text.labelLow("Host: ${uri.scheme}://${uri.host}"),
          if (catalog?.servers.isNotEmpty == true)
            buildServers(catalog!, ColorScheme.of(context)),
          if (catalog?.notices.isNotEmpty == true)
            buildNotices(catalog!, ColorScheme.of(context)),
          if (widget.widgetUri.previewMxc != null)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: ClipRRect(
                borderRadius: BorderRadiusGeometry.circular(20),
                child: SizedBox(
                  height: 300,
                  child: Image(
                      fit: BoxFit.cover,
                      image: MatrixMxcImage(
                          Uri.parse(widget.widgetUri.previewMxc!),
                          doThumbnail: false,
                          doFullres: true,
                          (widget.room.client as MatrixClient).matrixClient)),
                ),
              ),
            ),
          tiamat.Button(
            text: "Add Widget",
            isLoading: addingWidget,
            onTap: () async {
              var comp = widget.room.client.getComponent<WidgetComponent>();
              if (comp != null) {
                setState(() {
                  addingWidget = true;
                });

                await ErrorUtils.tryRun(context, () async {
                  var avatar = widget.widgetUri.widgetAvatarMxc != null
                      ? Uri.tryParse(widget.widgetUri.widgetAvatarMxc!)
                      : null;
                  if (avatar == null && widget.pageIcon?.icon != null) {
                    avatar = await uploadPageIcon(widget.pageIcon!);
                  }
                  if (avatar == null && widget.iconAsset != null) {
                    avatar = await uploadIcon(widget.iconAsset!);
                  }
                  await comp.addWidget(
                      url: Uri.parse(fillNewValues(widget.widgetUri.widgetUrl)),
                      room: widget.room,
                      iconImageUrl: avatar,
                      widgetName: widget.widgetUri.widgetName ?? "Custom",
                      widgetType: widget.widgetUri.widgetType);
                });

                Navigator.of(context).pop();
              }
            },
          ),
          tiamat.Button.secondary(
            text: "Cancel",
            onTap: () => Navigator.of(context).pop(),
          ),
          tiamat.Text.error(
              "Widgets are hosted on external websites, and the code can be changed without notice. Do not use the widget if you do not trust the host.")
        ],
      ),
    );
  }
}
