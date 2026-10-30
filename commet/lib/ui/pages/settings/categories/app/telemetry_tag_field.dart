// Vommet: the diagnostics name tag box and the "early testing" banner, shared
// by the first-run diagnostics prompt and Settings › Privacy.
import 'package:commet/main.dart';
import 'package:commet/telemetry/telemetry_tag.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Highlighted box asking testers to turn diagnostics on and add a tag. It
/// only recommends: the choice itself stays with two equal buttons.
class TelemetryEarlyTestingBanner extends StatelessWidget {
  const TelemetryEarlyTestingBanner(
      {required this.body, this.heading, this.summary, super.key});

  final String? heading;
  final String body;
  final String? summary;

  @override
  Widget build(BuildContext context) {
    final colors = ColorScheme.of(context);
    final accent = colors.primary;
    // Tinted over the theme's own surface with the theme's normal text colour
    // on top, so it stays readable in light and dark themes alike.
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Color.alphaBlend(accent.withValues(alpha: 0.14), colors.surface),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.7)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.science_outlined, color: accent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (heading != null) ...[
                  Text(heading!,
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: colors.onSurface)),
                  const SizedBox(height: 4),
                ],
                Text(body, style: TextStyle(color: colors.onSurface)),
                if (summary != null) ...[
                  const SizedBox(height: 6),
                  Text(summary!,
                      style: TextStyle(color: colors.onSurface.withAlpha(200))),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The optional diagnostics name tag box (Vommet issue 133). Empty unless the
/// user types one; never filled in from their account or display name.
///
/// With [autoSave] (Settings) the tag is saved when editing finishes, not on
/// every keystroke: a report sent mid-typing would otherwise carry a
/// half-typed tag. Without it (first-run prompt) the owner saves it, together
/// with the consent answer.
class TelemetryTagField extends StatefulWidget {
  const TelemetryTagField(
      {this.controller,
      this.enabled = true,
      this.showLabel = false,
      this.autoSave = true,
      this.showWarning = true,
      super.key});

  /// Holds the typed tag. When null the field keeps its own, starting from
  /// the saved tag.
  final TextEditingController? controller;

  /// A disabled box can't be typed in (on the prompt: until "Yes").
  final bool enabled;
  final bool showLabel;
  final bool autoSave;

  /// The amber "won't be anonymous" box while a tag is typed.
  final bool showWarning;

  @override
  State<TelemetryTagField> createState() => _TelemetryTagFieldState();
}

class _TelemetryTagFieldState extends State<TelemetryTagField> {
  TextEditingController? _own;
  final FocusNode _focus = FocusNode();

  TextEditingController get _controller =>
      widget.controller ??
      (_own ??= TextEditingController(
          text: TelemetryTag.normalize(preferences.telemetryTag.value) ?? ""));

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _commit();
    });
  }

  @override
  void dispose() {
    _commit(rebuild: false);
    _focus.dispose();
    _own?.dispose();
    super.dispose();
  }

  String? get _saved => TelemetryTag.normalize(preferences.telemetryTag.value);

  Future<void> _commit({bool rebuild = true}) async {
    if (!widget.autoSave || !widget.enabled) return;
    final text = _controller.text;
    if (!TelemetryTag.isValid(text)) return;
    final tag = TelemetryTag.normalize(text);
    if (tag != _saved) await preferences.telemetryTag.set(tag);
    if (rebuild && mounted) setState(() {});
  }

  String get _status {
    if (!widget.enabled) return telemetryTagOff;
    final shown =
        widget.autoSave ? _saved : TelemetryTag.normalize(_controller.text);
    return shown == null ? telemetryTagEmpty : telemetryTagSet(shown);
  }

  @override
  Widget build(BuildContext context) {
    final text = _controller.text;
    final valid = TelemetryTag.isValid(text);
    final tagged = TelemetryTag.normalize(text) != null;
    final unsaved = widget.autoSave &&
        widget.enabled &&
        valid &&
        TelemetryTag.normalize(text) != _saved;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.showLabel) ...[
          tiamat.Text.labelEmphasised(privacyNameTagHeader),
          const SizedBox(height: 4),
        ],
        TextField(
          controller: _controller,
          enabled: widget.enabled,
          maxLength: TelemetryTag.maxLength,
          autocorrect: false,
          enableSuggestions: false,
          inputFormatters: [
            FilteringTextInputFormatter.allow(TelemetryTag.allowedChars),
            const _UpperCaseFormatter(),
          ],
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(
            hintText: telemetryTagHint,
            prefixIcon: const Icon(Icons.badge_outlined),
            errorText: valid ? null : privacyNameTagInvalid,
            suffixIcon: text.isEmpty || !widget.enabled
                ? null
                : IconButton(
                    tooltip: privacyNameTagClear,
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      _controller.clear();
                      _commit();
                      setState(() {});
                    },
                  ),
          ),
          focusNode: _focus,
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _commit(),
          onTapOutside: (_) => _focus.unfocus(),
        ),
        tiamat.Text.labelLow(_status),
        if (unsaved) tiamat.Text.labelLow(telemetryTagUnsaved),
        if (widget.showWarning && widget.enabled && tagged) ...[
          const SizedBox(height: 8),
          const _NotAnonymousWarning(),
        ],
      ],
    );
  }
}

/// Amber warning shown while a tag is set: the reports are no longer
/// pseudonymous.
class _NotAnonymousWarning extends StatelessWidget {
  const _NotAnonymousWarning();

  @override
  Widget build(BuildContext context) {
    final colors = ColorScheme.of(context);
    // Amber warning tinted over the theme's own surface, with the theme's
    // normal text colour on top, so it stays readable in light and dark
    // themes alike (theme container pairs aren't reliable across themes).
    final dark = Theme.of(context).brightness == Brightness.dark;
    final warnAccent = dark ? Colors.amber.shade300 : Colors.amber.shade800;
    final warnBackground = Color.alphaBlend(
        Colors.amber.withValues(alpha: dark ? 0.14 : 0.18), colors.surface);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: warnBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: warnAccent),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.badge_outlined, color: warnAccent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(privacyNameTagWarningTitle,
                    style: TextStyle(
                        fontWeight: FontWeight.bold, color: colors.onSurface)),
                const SizedBox(height: 4),
                Text(privacyNameTagWarningBody,
                    style: TextStyle(color: colors.onSurface)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Shows the tag in capitals while typing, as it will be saved and sent.
class _UpperCaseFormatter extends TextInputFormatter {
  const _UpperCaseFormatter();

  @override
  TextEditingValue formatEditUpdate(
          TextEditingValue oldValue, TextEditingValue newValue) =>
      newValue.copyWith(text: newValue.text.toUpperCase());
}

String get telemetryEarlyHeading =>
    Intl.message("Early testing: please say yes",
        name: "telemetryEarlyHeading",
        desc: "Heading of the early-testing banner on the diagnostics prompt");

String get telemetryEarlyPrompt => Intl.message(
    "While Vommet is in early testing, we highly recommend turning on diagnostics and adding a name tag. It's the easiest way for the developers to track down bugs you run into.",
    name: "telemetryEarlyPrompt",
    desc: "Early-testing banner on the diagnostics prompt");

String get telemetryEarlySummary => Intl.message(
    "Diagnostics are timings, errors and your device type, never your messages or what you say in calls. The name tag only lets the developers find your reports.",
    name: "telemetryEarlySummary",
    desc: "Second line of the early-testing banner on the diagnostics prompt");

String get telemetryEarlySettings => Intl.message(
    "While Vommet is in early testing, we highly recommend adding a name tag (with Send diagnostics on). It's the easiest way for the developers to track down bugs you run into. The tag only lets them find your reports; diagnostics never include your messages or what you say in calls.",
    name: "telemetryEarlySettings",
    desc:
        "Early-testing banner next to the name tag in privacy settings; Send diagnostics is the toggle above it");

String get telemetryTagSameEverywhere => Intl.message(
    "Use the same tag on each device so your reports are grouped together.",
    name: "telemetryTagSameEverywhere",
    desc: "Under the early-testing banner in the name tag settings");

String get telemetryTagHint =>
    Intl.message("e.g. the name you use in the testers' chat",
        name: "telemetryTagHint", desc: "Hint in the empty name tag box");

String get telemetryTagOff => Intl.message(
    "Choose “Yes” to add a tag. It's only ever sent with diagnostics.",
    name: "telemetryTagOff",
    desc:
        "Under the name tag box on the diagnostics prompt before Yes is chosen; Yes is the button that turns diagnostics on");

String get telemetryTagEmpty => Intl.message(
    "Leave it empty to stay pseudonymous. Letters, numbers, spaces, - and _; saved in capitals.",
    name: "telemetryTagEmpty",
    desc: "Under the empty name tag box");

String telemetryTagSet(String tag) => Intl.message(
    "Sent with your reports as $tag. The developers will know these reports are yours.",
    args: [tag],
    name: "telemetryTagSet",
    desc: "Under the name tag box when a tag is set");

String get telemetryTagUnsaved => Intl.message(
    "Press Enter or tap outside the box to save your change.",
    name: "telemetryTagUnsaved",
    desc:
        "Under the name tag box in settings while it holds an unsaved change");

String get privacyNameTagHeader => Intl.message("Name tag (optional)",
    name: "privacyNameTagHeader",
    desc: "Header of the diagnostics name tag panel");

String get privacyNameTagInvalid => Intl.message(
    "Letters, numbers, spaces, -, and _ only, not starting or ending with a space",
    name: "privacyNameTagInvalid",
    desc: "Error under the name tag field when it has invalid characters");

String get privacyNameTagClear => Intl.message("Clear",
    name: "privacyNameTagClear",
    desc: "Tooltip of the button clearing the name tag");

String get privacyNameTagWarningTitle =>
    Intl.message("Your reports won't be anonymous",
        name: "privacyNameTagWarningTitle",
        desc: "Warning title when a name tag is set");

String get privacyNameTagWarningBody => Intl.message(
    "The developers will know these reports are yours. Use the same tag on each device so they can be grouped together. Leave it empty to stay pseudonymous.",
    name: "privacyNameTagWarningBody",
    desc: "Warning body when a name tag is set");
