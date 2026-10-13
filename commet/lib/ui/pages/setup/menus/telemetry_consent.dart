import 'dart:async';

import 'package:commet/main.dart';
import 'package:commet/ui/pages/setup/setup_menu.dart';
import 'package:commet/utils/links/link_utils.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;
import 'package:intl/intl.dart';

/// Shared wording for the consent screen and Settings › Privacy.
class TelemetryText {
  static String get title => telemetryConsentTitle;

  /// Vommet: shown in bold under the title of the consent screen. It asks
  /// clearly, but both answers stay equally easy to pick.
  static String get encourage => telemetryConsentEncourage;

  static String get what => telemetryConsentWhat;

  static String get never => telemetryConsentNever;

  static String get how => telemetryConsentHow;

  static String get change => telemetryConsentChange;

  static final privacyUrl = Uri.parse("https://vommet.app/privacy");
}

class TelemetryConsentSetup implements SetupMenu {
  final StreamController<SetupMenuState> controller = StreamController();

  @override
  Widget builder(BuildContext context) => const _TelemetryConsentView();

  @override
  Stream<SetupMenuState> get onStateChanged => controller.stream;

  @override
  SetupMenuState state = SetupMenuState.canProgress;

  // Pressing Next without choosing leaves the answer unset: nothing is sent,
  // and the question comes back next launch. No choice is made for the user.
  @override
  Future<void> submit() async {}
}

class _TelemetryConsentView extends StatefulWidget {
  const _TelemetryConsentView();

  @override
  State<_TelemetryConsentView> createState() => _TelemetryConsentViewState();
}

class _TelemetryConsentViewState extends State<_TelemetryConsentView> {
  @override
  Widget build(BuildContext context) {
    final choice = preferences.telemetryConsent.value;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        tiamat.Text.largeTitle(TelemetryText.title),
        const SizedBox(height: 8),
        Text(
          TelemetryText.encourage,
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        tiamat.Text.label(TelemetryText.what),
        const SizedBox(height: 8),
        tiamat.Text.label(TelemetryText.never),
        const SizedBox(height: 8),
        tiamat.Text.label(TelemetryText.how),
        const SizedBox(height: 8),
        tiamat.Text.label(TelemetryText.change),
        const SizedBox(height: 8),
        Text.rich(TextSpan(
            style: const TextStyle(decoration: TextDecoration.underline),
            text: telemetryConsentFullDetails,
            recognizer: TapGestureRecognizer()
              ..onTap = () =>
                  LinkUtils.open(TelemetryText.privacyUrl, context: context))),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _ChoiceButton(
              text: telemetryConsentYes,
              selected: choice == true,
              onTap: () => _choose(true),
            ),
            _ChoiceButton(
              text: telemetryConsentNo,
              selected: choice == false,
              onTap: () => _choose(false),
            ),
          ],
        ),
      ],
    );

    // Vommet: the app icon next to the text (above it on narrow screens),
    // so the screen doesn't look empty.
    const icon = Image(
      image:
          AssetImage("assets/images/app_icon/app_icon_transparent_cropped.png"),
      filterQuality: FilterQuality.medium,
    );
    return LayoutBuilder(builder: (context, constraints) {
      if (constraints.maxWidth < 560) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(width: 56, height: 56, child: icon),
            const SizedBox(height: 12),
            content,
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(width: 88, height: 88, child: icon),
          const SizedBox(width: 20),
          Expanded(child: content),
        ],
      );
    });
  }

  Future<void> _choose(bool value) async {
    await preferences.telemetryConsent.set(value);
    if (mounted) setState(() {});
  }
}

class _ChoiceButton extends StatelessWidget {
  const _ChoiceButton(
      {required this.text, required this.selected, required this.onTap});
  final String text;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Both choices look the same until picked: neither is the "default".
    return selected
        ? tiamat.Button(text: "✓ $text", onTap: onTap)
        : tiamat.Button.secondary(text: text, onTap: onTap);
  }
}

String get telemetryConsentTitle => Intl.message("Help improve Vommet?",
    name: "telemetryConsentTitle",
    desc: "Title of the diagnostics consent screen");

String get telemetryConsentEncourage => Intl.message(
    "If you're testing Vommet, we highly encourage saying yes: it's the easiest way for us to pinpoint and fix the bugs you report.",
    name: "telemetryConsentEncourage",
    desc: "Bold line under the title of the diagnostics consent screen");

String get telemetryConsentWhat => Intl.message(
    "Vommet can send diagnostics to its developers: how long things take (like sending a photo, starting up or joining a call), when something goes wrong, and what kind of device you're on.",
    name: "telemetryConsentWhat",
    desc:
        "What diagnostics contain; on the consent screen and in privacy settings");

String get telemetryConsentNever => Intl.message(
    "We never collect what you write, say or share: no messages, no voice messages, no call audio or video, no photos, videos or files, no file names, no names of people or rooms. This applies to every chat, encrypted or not.",
    name: "telemetryConsentNever",
    desc:
        "What diagnostics never contain; on the consent screen and in privacy settings");

String get telemetryConsentHow => Intl.message(
    "Reports are filed under a random ID, not your Matrix account. They aren't fully anonymous: details like file sizes and times could be matched to your activity by someone who runs the server. Your IP address isn't stored, and everything is deleted after 30 days.",
    name: "telemetryConsentHow",
    desc:
        "How diagnostics reports are stored; on the consent screen and in privacy settings");

String get telemetryConsentChange => Intl.message(
    "You can change your mind any time in Settings › Privacy, where you can also see exactly what has been sent and delete it.",
    name: "telemetryConsentChange",
    desc:
        "How to change the diagnostics choice later; Settings › Privacy is the settings path");

String get telemetryConsentFullDetails => Intl.message("Full details",
    name: "telemetryConsentFullDetails",
    desc: "Link that opens the full diagnostics privacy details");

String get telemetryConsentYes => Intl.message("Yes, send diagnostics",
    name: "telemetryConsentYes",
    desc: "Button that agrees to send diagnostics");

String get telemetryConsentNo => Intl.message("No thanks",
    name: "telemetryConsentNo",
    desc: "Button that declines sending diagnostics");
