import 'dart:async';

import 'package:commet/main.dart';
import 'package:commet/telemetry/telemetry.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/ui/pages/settings/categories/app/boolean_preference_toggle.dart';
import 'package:commet/ui/pages/setup/menus/telemetry_consent.dart';
import 'package:commet/utils/links/link_utils.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class PrivacySettingsPage extends StatefulWidget {
  const PrivacySettingsPage({super.key});

  @override
  State<PrivacySettingsPage> createState() => _PrivacySettingsPageState();
}

class _PrivacySettingsPageState extends State<PrivacySettingsPage> {
  StreamSubscription? _sentSub;
  StreamSubscription? _consentSub;
  bool _showSent = false;
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    _sentSub = Telemetry.onSentChanged.listen((_) {
      if (mounted) setState(() {});
    });
    _consentSub = preferences.telemetryConsent.onChanged.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _sentSub?.cancel();
    _consentSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final id = preferences.telemetryInstallId.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        tiamat.Panel(
          header: "Diagnostics",
          mode: tiamat.TileType.surfaceContainerLow,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              NullableBooleanPreferenceToggle(
                preference: preferences.telemetryConsent,
                title: "Send diagnostics",
                description: TelemetryText.what,
              ),
              const SizedBox(height: 8),
              tiamat.Text.labelLow(TelemetryText.never),
              const SizedBox(height: 4),
              tiamat.Text.labelLow(TelemetryText.how),
              const SizedBox(height: 4),
              Text.rich(TextSpan(
                  style: const TextStyle(decoration: TextDecoration.underline),
                  text: "Full details",
                  recognizer: TapGestureRecognizer()
                    ..onTap = () => LinkUtils.open(TelemetryText.privacyUrl,
                        context: context))),
            ],
          ),
        ),
        const SizedBox(height: 10),
        if (id != null)
          tiamat.Panel(
            header: "Your diagnostics ID",
            mode: tiamat.TileType.surfaceContainerLow,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                tiamat.Text.labelLow(
                    "If you report a problem, sharing this ID lets the "
                    "developers find your diagnostics. It isn't linked to "
                    "your account."),
                const SizedBox(height: 8),
                Row(children: [
                  Flexible(child: SelectableText(id)),
                  IconButton(
                    tooltip: "Copy",
                    icon: const Icon(Icons.copy, size: 18),
                    onPressed: () => Clipboard.setData(ClipboardData(text: id)),
                  ),
                ]),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  tiamat.Button.danger(
                    text: "Delete my diagnostics",
                    isLoading: _deleting,
                    onTap: _delete,
                  ),
                ]),
              ],
            ),
          ),
        const SizedBox(height: 10),
        tiamat.Panel(
          header: "What's been sent",
          mode: tiamat.TileType.surfaceContainerLow,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              tiamat.Text.labelLow(Telemetry.sent.isEmpty
                  ? "Nothing has been sent since Vommet started."
                  : "${Telemetry.sent.length} reports sent since Vommet "
                      "started. This is exactly what left your device."),
              if (Telemetry.sent.isNotEmpty) ...[
                const SizedBox(height: 8),
                tiamat.Button.secondary(
                  text: _showSent ? "Hide reports" : "Show reports",
                  onTap: () => setState(() => _showSent = !_showSent),
                ),
              ],
              if (_showSent)
                for (final b in Telemetry.sent.reversed) ...[
                  const SizedBox(height: 8),
                  tiamat.Text.labelLow(
                      DateFormat.yMd().add_Hms().format(b.time)),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: ColorScheme.of(context).surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SelectableText(b.json,
                        style: const TextStyle(
                            fontFamily: "monospace", fontSize: 12)),
                  ),
                ],
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _delete() async {
    final ok = await AdaptiveDialog.confirmation(context,
        title: "Delete diagnostics",
        prompt: "Ask the server to delete every report sent from this device, "
            "and start over with a new ID?",
        confirmationText: "Delete",
        dangerous: true);
    if (ok != true) return;
    setState(() => _deleting = true);
    final done = await Telemetry.deleteMyData();
    if (!mounted) return;
    setState(() => _deleting = false);
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
        content: Text(done
            ? "Your diagnostics were deleted."
            : "Couldn't reach the server. Nothing was deleted; try again "
                "later.")));
  }
}
