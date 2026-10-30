import 'package:commet/main.dart';
import 'package:commet/ui/pages/settings/categories/app/auto_download_settings.dart';
import 'package:commet/utils/media_auto_download.dart';
import 'package:commet/utils/picture_shrink.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Vommet issue 128: Data and storage › Sending pictures: when pictures are
/// sent smaller by default, and how small. Each picture can still be
/// switched in the attachment dialog.
class SendSmallerCard extends StatefulWidget {
  const SendSmallerCard({super.key});

  @override
  State<SendSmallerCard> createState() => _SendSmallerCardState();
}

class _SendSmallerCardState extends State<SendSmallerCard> {
  String get labelSendingPictures => Intl.message("Sending pictures",
      desc: "Header for the settings about sending pictures smaller",
      name: "labelSendingPictures");

  String get labelSendSmallerPictures => Intl.message("Send smaller pictures",
      desc: "Setting for when pictures are sent smaller by default",
      name: "labelSendSmallerPictures");

  String get labelSendSmallerNever => Intl.message("Never",
      desc: "Pictures are never sent smaller by default",
      name: "labelSendSmallerNever");

  String get labelSendSmallerMobileData => Intl.message("On mobile data",
      desc: "Pictures are sent smaller by default on mobile data",
      name: "labelSendSmallerMobileData");

  String get labelSendSmallerAlways => Intl.message("Always",
      desc: "Pictures are always sent smaller by default",
      name: "labelSendSmallerAlways");

  String get labelSendSmallerHint =>
      Intl.message("You can still change it for each picture before sending.",
          desc: "Under the 'Send smaller pictures' setting",
          name: "labelSendSmallerHint");

  String get labelSendSmallerSize => Intl.message("Size",
      desc: "Setting for how small smaller pictures are",
      name: "labelSendSmallerSize");

  String get labelSendSmallerSmall => Intl.message("Small",
      desc: "Smaller pictures size choice: 1280 px",
      name: "labelSendSmallerSmall");

  String get labelSendSmallerStandard => Intl.message("Standard",
      desc: "Smaller pictures size choice: 2048 px",
      name: "labelSendSmallerStandard");

  String get labelSendSmallerLarge => Intl.message("Large",
      desc: "Smaller pictures size choice: 2560 px",
      name: "labelSendSmallerLarge");

  String labelSendSmallerSizeHint(int pixels) =>
      Intl.message("Longest side $pixels px. Pictures are never made bigger.",
          desc: "Under the smaller pictures size setting",
          args: [pixels],
          name: "labelSendSmallerSizeHint");

  String get labelSendSmallerNote => Intl.message(
      "GIFs, animated pictures and videos are always sent as they are. Smaller pictures never keep hidden info (location, camera).",
      desc: "Explains what sending pictures smaller covers",
      name: "labelSendSmallerNote");

  SendSmallerMode get mode =>
      SendSmallerMode.fromKey(preferences.sendSmallerPictures.value);

  SendSmallerSize get size =>
      SendSmallerSize.fromKey(preferences.sendSmallerPicturesSize.value);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Desktops and web are never on mobile data, so that choice acts like
    // Never there and isn't offered.
    final phone = MediaAutoDownload.tracksNetwork;
    var shown = mode;
    if (!phone && shown == SendSmallerMode.mobileData) {
      shown = SendSmallerMode.never;
    }

    Widget hint(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
          child: Text(text,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        );

    Widget label(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
          child: Text(text,
              style: theme.textTheme.bodyLarge
                  ?.copyWith(color: theme.colorScheme.onSurface)),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AutoDownloadSettingsCard(title: labelSendingPictures, children: [
          label(labelSendSmallerPictures),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<SendSmallerMode>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                    value: SendSmallerMode.never,
                    label: Text(labelSendSmallerNever)),
                if (phone)
                  ButtonSegment(
                      value: SendSmallerMode.mobileData,
                      label: Text(labelSendSmallerMobileData)),
                ButtonSegment(
                    value: SendSmallerMode.always,
                    label: Text(labelSendSmallerAlways)),
              ],
              selected: {shown},
              onSelectionChanged: (s) async {
                await preferences.sendSmallerPictures.set(s.first.key);
                if (mounted) setState(() {});
              },
            ),
          ),
          hint(labelSendSmallerHint),
          label(labelSendSmallerSize),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<SendSmallerSize>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                    value: SendSmallerSize.small,
                    label: Text(labelSendSmallerSmall)),
                ButtonSegment(
                    value: SendSmallerSize.standard,
                    label: Text(labelSendSmallerStandard)),
                ButtonSegment(
                    value: SendSmallerSize.large,
                    label: Text(labelSendSmallerLarge)),
              ],
              selected: {size},
              onSelectionChanged: (s) async {
                await preferences.sendSmallerPicturesSize.set(s.first.key);
                if (mounted) setState(() {});
              },
            ),
          ),
          hint(labelSendSmallerSizeHint(size.longestEdge)),
          const SizedBox(height: 14),
        ]),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 14),
          child: Text(labelSendSmallerNote,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ),
      ],
    );
  }
}
