import 'dart:async';

import 'package:commet/config/room_encryption_default.dart';
import 'package:commet/main.dart';
import 'package:commet/telemetry/telemetry.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/ui/pages/settings/categories/app/boolean_preference_toggle.dart';
import 'package:commet/ui/pages/settings/categories/app/telemetry_tag_field.dart';
import 'package:commet/ui/pages/settings/search/settings_search.dart';
import 'package:commet/ui/pages/setup/menus/telemetry_consent.dart';
import 'package:commet/utils/links/link_utils.dart';
import 'package:commet/utils/links/trusted_link_domains.dart';
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
        // Vommet: where the create-room encryption switch starts (Vommet
        // issue 524).
        tiamat.Panel(
          header: encryptionSettingsHeader,
          mode: tiamat.TileType.surfaceContainerLow,
          child: BooleanPreferenceToggle(
            preference: encryptNewRoomsByDefault,
            title: encryptNewRoomsTitle,
            description: encryptNewRoomsDescription,
          ),
        ),
        const SizedBox(height: 10),
        tiamat.Panel(
          header: privacyDiagnosticsHeader,
          mode: tiamat.TileType.surfaceContainerLow,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              NullableBooleanPreferenceToggle(
                preference: preferences.telemetryConsent,
                title: privacySendDiagnostics,
                description: TelemetryText.what,
              ),
              const SizedBox(height: 8),
              tiamat.Text.labelLow(TelemetryText.never),
              const SizedBox(height: 4),
              tiamat.Text.labelLow(TelemetryText.how),
              const SizedBox(height: 4),
              Text.rich(TextSpan(
                  style: const TextStyle(decoration: TextDecoration.underline),
                  text: privacyFullDetails,
                  recognizer: TapGestureRecognizer()
                    ..onTap = () => LinkUtils.open(TelemetryText.privacyUrl,
                        context: context))),
            ],
          ),
        ),
        const SizedBox(height: 10),
        const _NameTagPanel(),
        const SizedBox(height: 10),
        if (id != null)
          tiamat.Panel(
            header: privacyDiagnosticsIdHeader,
            mode: tiamat.TileType.surfaceContainerLow,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                tiamat.Text.labelLow(privacyDiagnosticsIdExplain),
                const SizedBox(height: 8),
                Row(children: [
                  Flexible(child: SelectableText(id)),
                  IconButton(
                    tooltip: privacyCopy,
                    icon: const Icon(Icons.copy, size: 18),
                    onPressed: () => Clipboard.setData(ClipboardData(text: id)),
                  ),
                ]),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  tiamat.Button.danger(
                    text: privacyDeleteMyDiagnostics,
                    isLoading: _deleting,
                    onTap: _delete,
                  ),
                ]),
              ],
            ),
          ),
        const SizedBox(height: 10),
        tiamat.Panel(
          header: privacySentHeader,
          mode: tiamat.TileType.surfaceContainerLow,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              tiamat.Text.labelLow(Telemetry.sent.isEmpty
                  ? privacyNothingSent
                  : privacyReportsSent(Telemetry.sent.length)),
              if (Telemetry.sent.isNotEmpty) ...[
                const SizedBox(height: 8),
                tiamat.Button.secondary(
                  text: _showSent ? privacyHideReports : privacyShowReports,
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
        // Vommet issue 503: domains trusted from the Open Link prompt.
        const TrustedLinkDomainsPanel(),
      ],
    );
  }

  Future<void> _delete() async {
    final ok = await AdaptiveDialog.confirmation(context,
        title: privacyDeleteTitle,
        prompt: privacyDeletePrompt,
        confirmationText: privacyDeleteConfirm,
        dangerous: true);
    if (ok != true) return;
    setState(() => _deleting = true);
    final done = await Telemetry.deleteMyData();
    if (!mounted) return;
    setState(() => _deleting = false);
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(done ? privacyDeleted : privacyDeleteFailed)));
  }
}

/// Vommet: optional diagnostics name tag (Vommet issue 133), with the
/// early-testing recommendation next to it.
class _NameTagPanel extends StatelessWidget {
  const _NameTagPanel();

  @override
  Widget build(BuildContext context) {
    return SettingsSearchTarget(
      ids: const ["telemetry_tag"],
      child: tiamat.Panel(
        header: privacyNameTagHeader,
        mode: tiamat.TileType.surfaceContainerLow,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TelemetryEarlyTestingBanner(body: telemetryEarlySettings),
            const SizedBox(height: 8),
            tiamat.Text.labelLow(telemetryTagSameEverywhere),
            const SizedBox(height: 8),
            const TelemetryTagField(),
          ],
        ),
      ),
    );
  }
}

String get privacyDiagnosticsHeader => Intl.message("Diagnostics",
    name: "privacyDiagnosticsHeader",
    desc: "Header of the diagnostics panel in privacy settings");

String get privacySendDiagnostics => Intl.message("Send diagnostics",
    name: "privacySendDiagnostics",
    desc: "Title of the toggle that sends diagnostics");

String get privacyFullDetails => Intl.message("Full details",
    name: "privacyFullDetails",
    desc: "Link that opens the full diagnostics privacy details");

String get privacyDiagnosticsIdHeader => Intl.message("Your diagnostics ID",
    name: "privacyDiagnosticsIdHeader",
    desc: "Header of the panel showing the diagnostics ID");

String get privacyDiagnosticsIdExplain => Intl.message(
    "If you report a problem, sharing this ID lets the developers find your diagnostics. It isn't linked to your account.",
    name: "privacyDiagnosticsIdExplain",
    desc: "Explanation of the diagnostics ID");

String get privacyCopy => Intl.message("Copy",
    name: "privacyCopy",
    desc: "Tooltip of the button copying the diagnostics ID");

String get privacyDeleteMyDiagnostics => Intl.message("Delete my diagnostics",
    name: "privacyDeleteMyDiagnostics",
    desc: "Button that deletes the diagnostics sent from this device");

String get privacySentHeader => Intl.message("What's been sent",
    name: "privacySentHeader",
    desc: "Header of the panel listing diagnostics reports sent");

String get privacyNothingSent =>
    Intl.message("Nothing has been sent since Vommet started.",
        name: "privacyNothingSent",
        desc: "Shown when no diagnostics reports were sent");

String privacyReportsSent(int count) => Intl.plural(count,
    one:
        "1 report sent since Vommet started. This is exactly what left your device.",
    other:
        "$count reports sent since Vommet started. This is exactly what left your device.",
    args: [count],
    name: "privacyReportsSent",
    desc: "Number of diagnostics reports sent since the app started");

String get privacyHideReports => Intl.message("Hide reports",
    name: "privacyHideReports",
    desc: "Button that hides the sent diagnostics reports");

String get privacyShowReports => Intl.message("Show reports",
    name: "privacyShowReports",
    desc: "Button that shows the sent diagnostics reports");

String get privacyDeleteTitle => Intl.message("Delete diagnostics",
    name: "privacyDeleteTitle",
    desc: "Title of the delete diagnostics confirmation");

String get privacyDeletePrompt => Intl.message(
    "Ask the server to delete every report sent from this device, and start over with a new ID?",
    name: "privacyDeletePrompt",
    desc: "Body of the delete diagnostics confirmation");

String get privacyDeleteConfirm => Intl.message("Delete",
    name: "privacyDeleteConfirm",
    desc: "Confirm button of the delete diagnostics dialog");

String get privacyDeleted => Intl.message("Your diagnostics were deleted.",
    name: "privacyDeleted",
    desc: "Snackbar after the diagnostics were deleted");

String get privacyDeleteFailed => Intl.message(
    "Couldn't reach the server. Nothing was deleted; try again later.",
    name: "privacyDeleteFailed",
    desc: "Snackbar when deleting diagnostics failed");
