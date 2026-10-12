import 'package:commet/client/client.dart';
import 'package:commet/client/components/widgets/widget_component.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/matrix_mxc_image_provider.dart';
import 'package:commet/utils/custom_uri.dart';
import 'package:commet/utils/error_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'dart:ui' as ui;

import 'package:tiamat/tiamat.dart' as tiamat;

class AddWidgetDialog extends StatefulWidget {
  const AddWidgetDialog({
    super.key,
    required this.widgetUri,
    required this.room,
    this.iconAsset,
  });

  final AddWidgetURI widgetUri;
  final Room room;

  /// Vommet: a bundled SVG icon (from the widget picker), uploaded as the
  /// widget's avatar when it's added.
  final String? iconAsset;

  @override
  State<AddWidgetDialog> createState() => _AddWidgetDialogState();
}

class _AddWidgetDialogState extends State<AddWidgetDialog> {
  bool addingWidget = false;

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
                  if (avatar == null && widget.iconAsset != null) {
                    avatar = await uploadIcon(widget.iconAsset!);
                  }
                  await comp.addWidget(
                      url: Uri.parse(widget.widgetUri.widgetUrl),
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
