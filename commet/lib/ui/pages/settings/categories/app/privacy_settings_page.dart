import 'dart:async';

import 'package:commet/main.dart';
import 'package:commet/telemetry/telemetry.dart';
import 'package:commet/telemetry/telemetry_tag.dart';
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
        const _NameTagPanel(),
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

/// Vommet: optional diagnostics name tag (Vommet issue 133). Empty unless the
/// user types one; never filled in from their account or display name.
class _NameTagPanel extends StatefulWidget {
  const _NameTagPanel();

  @override
  State<_NameTagPanel> createState() => _NameTagPanelState();
}

class _NameTagPanelState extends State<_NameTagPanel> {
  late final TextEditingController _controller =
      TextEditingController(text: preferences.telemetryTag.value ?? "");

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save(String text) async {
    if (!TelemetryTag.isValid(text)) {
      setState(() {});
      return;
    }
    await preferences.telemetryTag.set(TelemetryTag.normalize(text));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final text = _controller.text;
    final valid = TelemetryTag.isValid(text);
    final tagged = TelemetryTag.normalize(text) != null;
    final colors = ColorScheme.of(context);
    return tiamat.Panel(
      header: "Name tag (optional)",
      mode: tiamat.TileType.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          tiamat.Text.labelLow(
              "Type a name, for example the one you use in the testers' chat, "
              "so the developers can group your reports across your devices. "
              "Leave it empty to stay pseudonymous."),
          const SizedBox(height: 8),
          TextField(
            controller: _controller,
            maxLength: TelemetryTag.maxLength,
            autocorrect: false,
            enableSuggestions: false,
            inputFormatters: [
              FilteringTextInputFormatter.allow(TelemetryTag.allowedChars),
            ],
            decoration: InputDecoration(
              hintText: "No tag",
              errorText: valid
                  ? null
                  : "Letters, numbers, spaces, - and _ only, "
                      "not starting or ending with a space",
              suffixIcon: text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: "Clear",
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        _controller.clear();
                        _save("");
                      },
                    ),
            ),
            onChanged: _save,
          ),
          if (tagged) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.tertiaryContainer,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colors.tertiary),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.badge_outlined, color: colors.onTertiaryContainer),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Your reports won't be anonymous",
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: colors.onTertiaryContainer)),
                        const SizedBox(height: 4),
                        Text(
                            "The developers will know these reports are "
                            "yours. Use the same tag on each device so they "
                            "can be grouped together. Leave it empty to stay "
                            "pseudonymous.",
                            style:
                                TextStyle(color: colors.onTertiaryContainer)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
