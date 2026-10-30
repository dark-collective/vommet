import 'package:commet/ui/pages/settings/categories/app/auto_download_settings.dart';
import 'package:commet/utils/call_data_saver.dart';
import 'package:commet/utils/media_auto_download.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Vommet issue 776: Data and storage › Calls: when calls use less data.
class CallDataSaverCard extends StatefulWidget {
  const CallDataSaverCard({super.key});

  @override
  State<CallDataSaverCard> createState() => _CallDataSaverCardState();
}

class _CallDataSaverCardState extends State<CallDataSaverCard> {
  String get labelCallDataSaverCalls => Intl.message("Calls",
      desc: "Header for the settings about how much data calls use",
      name: "labelCallDataSaverCalls");

  String get labelCallDataSaver => Intl.message("Use less data for calls",
      desc: "Setting for when calls send and receive less video and audio",
      name: "labelCallDataSaver");

  String get labelCallDataSaverNever => Intl.message("Never",
      desc: "Calls never use less data", name: "labelCallDataSaverNever");

  String get labelCallDataSaverRoaming => Intl.message("Roaming only",
      desc: "Calls use less data only while roaming",
      name: "labelCallDataSaverRoaming");

  String get labelCallDataSaverMobile => Intl.message("Mobile data and roaming",
      desc: "Calls use less data on mobile data and while roaming",
      name: "labelCallDataSaverMobile");

  String get labelCallDataSaverMetered => Intl.message("Metered connections",
      desc:
          "Calls use less data on metered connections (desktop wording of 'Mobile data and roaming')",
      name: "labelCallDataSaverMetered");

  String get labelCallDataSaverAlways => Intl.message("Always",
      desc: "Calls always use less data", name: "labelCallDataSaverAlways");

  String get labelCallDataSaverHint => Intl.message(
      "Your camera is sent at 360p, screen shares at 720p and 15 frames a second, and voice at a lower bitrate. Other people's video comes in at lower quality. Overrides the Voice and video settings while in use.",
      desc: "Explains what 'Use less data for calls' does",
      name: "labelCallDataSaverHint");

  CallDataSaverMode get mode => CallDataSaver.currentMode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Roaming is only known on phones; macOS and web never know the
    // network, so there only Never and Always are offered.
    final phone = MediaAutoDownload.tracksNetwork;
    final knowsNetwork = MediaAutoDownload.hasSettings;
    var shown = mode;
    if (!phone && shown == CallDataSaverMode.roaming) {
      shown = CallDataSaverMode.never;
    }
    if (!knowsNetwork && shown == CallDataSaverMode.mobile) {
      shown = CallDataSaverMode.never;
    }

    Widget option(CallDataSaverMode value, String text) => ListTile(
          dense: true,
          leading: Icon(
              value == shown
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: value == shown
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant),
          title: Text(text, style: theme.textTheme.bodyLarge),
          onTap: () async {
            await CallDataSaver.mode.set(value.name);
            if (mounted) setState(() {});
          },
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AutoDownloadSettingsCard(title: labelCallDataSaverCalls, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: Text(labelCallDataSaver,
                style: theme.textTheme.bodyLarge
                    ?.copyWith(color: theme.colorScheme.onSurface)),
          ),
          option(CallDataSaverMode.never, labelCallDataSaverNever),
          if (phone)
            option(CallDataSaverMode.roaming, labelCallDataSaverRoaming),
          if (knowsNetwork)
            option(CallDataSaverMode.mobile,
                phone ? labelCallDataSaverMobile : labelCallDataSaverMetered),
          option(CallDataSaverMode.always, labelCallDataSaverAlways),
          const SizedBox(height: 8),
        ]),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 14),
          child: Text(labelCallDataSaverHint,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ),
      ],
    );
  }
}
