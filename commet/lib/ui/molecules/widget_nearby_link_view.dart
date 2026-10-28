import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

String get widgetNearbyTitle => Intl.message("Open on a nearby device",
    desc:
        "Title of the dialog with a QR code that opens a widget on another device",
    name: "widgetNearbyTitle");

String get widgetNearbyMenuItem => Intl.message("Open on a nearby device",
    desc:
        "Widget menu item that shows a QR code to open the widget on another device",
    name: "widgetNearbyMenuItem");

String get widgetNearbyHint => Intl.message(
    "Scan with a phone or computer on the same Wi-Fi.",
    desc:
        "Short instruction under the QR code that opens a widget on another device",
    name: "widgetNearbyHint");

String get widgetNearbyCopyLink => Intl.message("Copy link",
    desc: "Button that copies the link that opens a widget on another device",
    name: "widgetNearbyCopyLink");

String get widgetNearbyHowItWorks => Intl.message("How this works",
    desc: "Expands an explanation of opening a widget on another device",
    name: "widgetNearbyHowItWorks");

String get widgetNearbyExplanation => Intl.message(
    "Vommet keeps running the widget and shares it on your local network. The other device doesn't sign in to your account: it shows the widget, and Vommet passes its messages to the room.",
    desc: "Explains how opening a widget on another device works",
    name: "widgetNearbyExplanation");

String get widgetNearbySameNetwork =>
    Intl.message("Both devices need to be on the same network.",
        desc: "Point in the explanation of opening a widget on another device",
        name: "widgetNearbySameNetwork");

String get widgetNearbyKeepOpen => Intl.message(
    "Keep Vommet open. The link stops working when you close the widget or Vommet.",
    desc: "Point in the explanation of opening a widget on another device",
    name: "widgetNearbyKeepOpen");

String get widgetNearbyCertificate => Intl.message(
    "The browser will warn that the connection isn't private. That's expected: the link uses a certificate Vommet made itself. Continue past the warning.",
    desc: "Point in the explanation of opening a widget on another device",
    name: "widgetNearbyCertificate");

String get widgetNearbyPrivate => Intl.message(
    "Anyone on your network with the link can use the widget as you until it closes, so keep the link to yourself.",
    desc: "Point in the explanation of opening a widget on another device",
    name: "widgetNearbyPrivate");

/// Vommet: the QR code that opens a widget on another device, with a short
/// instruction and an expandable explanation of what it does.
class WidgetNearbyLinkView extends StatefulWidget {
  const WidgetNearbyLinkView(
      {required this.url,
      this.qrImage,
      this.initiallyExpanded = false,
      super.key});

  final String url;
  final ImageProvider? qrImage;
  final bool initiallyExpanded;

  @override
  State<WidgetNearbyLinkView> createState() => _WidgetNearbyLinkViewState();
}

class _WidgetNearbyLinkViewState extends State<WidgetNearbyLinkView> {
  late bool expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.of(context);
    return SizedBox(
      width: 300,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: 8,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 300,
              width: 300,
              child: PrettyQrView.data(
                data: widget.url,
                errorCorrectLevel: QrErrorCorrectLevel.H,
                decoration: PrettyQrDecoration(
                    image: widget.qrImage == null
                        ? null
                        : PrettyQrDecorationImage(
                            scale: 0.20,
                            padding: const EdgeInsets.all(40),
                            filterQuality: FilterQuality.medium,
                            image: widget.qrImage!,
                          ),
                    quietZone: PrettyQrQuietZone.standard,
                    shape: const PrettyQrSmoothSymbol(color: Colors.white),
                    background: Colors.black),
              ),
            ),
          ),
          tiamat.Text.labelLow(widgetNearbyHint),
          SizedBox(
            height: 30,
            child: tiamat.TextButton(
              widgetNearbyCopyLink,
              icon: Icons.copy,
              onTap: () => Clipboard.setData(ClipboardData(text: widget.url)),
            ),
          ),
          InkWell(
            mouseCursor: WidgetStateMouseCursor.clickable,
            key: const ValueKey("widget-nearby-how"),
            borderRadius: BorderRadius.circular(6),
            onTap: () => setState(() => expanded = !expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                Icon(Icons.info_outline, size: 18, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(child: tiamat.Text(widgetNearbyHowItWorks)),
                Icon(expanded ? Icons.expand_less : Icons.expand_more,
                    color: scheme.onSurfaceVariant),
              ]),
            ),
          ),
          if (expanded)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 6,
              children: [
                tiamat.Text.labelLow(widgetNearbyExplanation),
                for (final point in [
                  widgetNearbySameNetwork,
                  widgetNearbyKeepOpen,
                  widgetNearbyCertificate,
                  widgetNearbyPrivate,
                ])
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    tiamat.Text.labelLow("•  "),
                    Expanded(child: tiamat.Text.labelLow(point)),
                  ]),
              ],
            ),
        ],
      ),
    );
  }
}
