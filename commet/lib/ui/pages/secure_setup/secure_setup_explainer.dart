import 'package:commet/ui/pages/secure_setup/secure_setup_widgets.dart';
import 'package:commet/utils/links/link_utils.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

const secureMessagingGuide = "https://vommet.app/help/secure-messaging";

/// Vommet issue 129: "What does this mean?", four offline cards.
class SecureSetupExplainer extends StatefulWidget {
  const SecureSetupExplainer({super.key});

  @override
  State<SecureSetupExplainer> createState() => _SecureSetupExplainerState();
}

class _SecureSetupExplainerState extends State<SecureSetupExplainer> {
  int slide = 0;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final slides = _slides(context);
    final (title, art, text) = slides[slide];
    return Material(
      color: t.colorScheme.surfaceContainer,
      child: SetupPage(
        title: secureExplainerTitle,
        onBack: () =>
            slide > 0 ? setState(() => slide--) : Navigator.of(context).pop(),
        children: [
          const SizedBox(height: 10),
          SetupTitle(title),
          const SizedBox(height: 22),
          Container(
            height: 270,
            alignment: Alignment.center,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                color: t.colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(18)),
            child: art,
          ),
          const SizedBox(height: 20),
          SetupBody(text),
        ],
        bottom: [
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var i = 0; i < slides.length; i++)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i == slide
                        ? t.colorScheme.primary
                        : t.colorScheme.surfaceContainerHighest),
              ),
          ]),
          const SizedBox(height: 14),
          SetupPrimaryButton(
              slide < slides.length - 1
                  ? secureExplainerNext
                  : secureExplainerGotIt,
              onPressed: () => slide < slides.length - 1
                  ? setState(() => slide++)
                  : Navigator.of(context).pop()),
          SetupTextLink(secureExplainerReadGuide,
              color: t.colorScheme.primary,
              onTap: () => LinkUtils.open(Uri.parse(secureMessagingGuide))),
        ],
      ),
    );
  }

  List<(String, Widget, String)> _slides(BuildContext c) {
    final t = Theme.of(c);
    Widget device(IconData icon, String label, bool ok) =>
        Column(mainAxisSize: MainAxisSize.min, children: [
          Stack(clipBehavior: Clip.none, children: [
            Icon(icon, size: 52, color: t.colorScheme.onSurface),
            Positioned(
                right: -8,
                bottom: -4,
                child: Icon(ok ? Icons.verified : Icons.help,
                    size: 22, color: ok ? setupGood : setupWarn)),
          ]),
          const SizedBox(height: 6),
          Text(label,
              style: t.textTheme.bodySmall
                  ?.copyWith(color: t.colorScheme.onSurfaceVariant)),
        ]);
    Widget arrowLock() => Padding(
          padding: const EdgeInsets.only(bottom: 22, left: 4, right: 4),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.lock, size: 18, color: setupGood),
            Icon(Icons.arrow_forward, size: 22, color: t.colorScheme.primary),
          ]),
        );
    Widget vouch() => Padding(
          padding: const EdgeInsets.only(bottom: 22, left: 8, right: 8),
          child: Icon(Icons.handshake_outlined,
              size: 24, color: t.colorScheme.primary),
        );
    Widget keyCard(IconData icon, String title, String sub, Color color) =>
        Container(
          width: 130,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 40, color: color),
            const SizedBox(height: 8),
            Text(title,
                style: t.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(sub,
                textAlign: TextAlign.center,
                style: t.textTheme.bodySmall
                    ?.copyWith(color: t.colorScheme.onSurfaceVariant)),
          ]),
        );
    Widget outcome(IconData icon, Color color, String title, String body) =>
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: color, size: 30),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: t.textTheme.titleSmall?.copyWith(
                      color: t.colorScheme.onSurface,
                      fontWeight: FontWeight.w700)),
              Text(body,
                  style: t.textTheme.bodyMedium?.copyWith(
                      color: t.colorScheme.onSurfaceVariant, height: 1.3)),
            ]),
          ),
        ]);

    return [
      (
        secureExplainerKeysTitle,
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          device(Icons.smartphone, secureExplainerYou, true),
          arrowLock(),
          Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.dns_outlined,
                size: 52, color: t.colorScheme.onSurfaceVariant),
            const SizedBox(height: 4),
            Icon(Icons.visibility_off_outlined,
                size: 22, color: t.colorScheme.onSurfaceVariant),
            const SizedBox(height: 4),
            Text(secureExplainerServer,
                style: t.textTheme.bodySmall
                    ?.copyWith(color: t.colorScheme.onSurfaceVariant)),
          ]),
          arrowLock(),
          device(Icons.smartphone, secureExplainerFriend, true),
        ]),
        secureExplainerKeysBody
      ),
      (
        secureExplainerTwoKeysTitle,
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          keyCard(Icons.door_front_door_outlined, secureExplainerPassword,
              secureExplainerPasswordSub, t.colorScheme.primary),
          keyCard(Icons.lock_outline, secureExplainerRecoveryKey,
              secureExplainerRecoveryKeySub, setupGood),
        ]),
        secureExplainerTwoKeysBody
      ),
      (
        secureExplainerVouchTitle,
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          device(Icons.smartphone, secureExplainerPhone, true),
          vouch(),
          device(Icons.laptop, secureExplainerLaptop, true),
          vouch(),
          device(Icons.tablet_android, secureExplainerNewTablet, false),
        ]),
        secureExplainerVouchBody
      ),
      (
        secureExplainerLoseTitle,
        Column(mainAxisSize: MainAxisSize.min, children: [
          outcome(Icons.check_circle, setupGood, secureExplainerLosePhone,
              secureExplainerLosePhoneBody),
          const SizedBox(height: 10),
          outcome(Icons.check_circle, setupGood, secureExplainerLoseAllWithKey,
              secureExplainerLoseAllWithKeyBody),
          const SizedBox(height: 10),
          outcome(Icons.cancel, t.colorScheme.error,
              secureExplainerLoseAllNoKey, secureExplainerLoseAllNoKeyBody),
        ]),
        secureExplainerLoseBody
      ),
    ];
  }
}

String get secureExplainerTitle => Intl.message("What does this mean?",
    name: "secureExplainerTitle",
    desc: "Title of the secure messaging explainer slides");

String get secureExplainerNext => Intl.message("Next",
    name: "secureExplainerNext",
    desc: "Button that goes to the next secure messaging explainer slide");

String get secureExplainerGotIt => Intl.message("Got it",
    name: "secureExplainerGotIt",
    desc: "Button on the last secure messaging explainer slide that closes it");

String get secureExplainerReadGuide => Intl.message("Read the full guide",
    name: "secureExplainerReadGuide",
    desc:
        "Link under the secure messaging explainer that opens the online guide");

String get secureExplainerKeysTitle => Intl.message("Only you hold the keys",
    name: "secureExplainerKeysTitle", desc: "Title of explainer slide 1");

String get secureExplainerYou => Intl.message("You",
    name: "secureExplainerYou",
    desc: "Label under your own device in explainer slide 1 (very short)");

String get secureExplainerServer => Intl.message("Server",
    name: "secureExplainerServer",
    desc: "Label under the server icon in explainer slide 1 (very short)");

String get secureExplainerFriend => Intl.message("Friend",
    name: "secureExplainerFriend",
    desc: "Label under a friend's device in explainer slide 1 (very short)");

String get secureExplainerKeysBody => Intl.message(
    "Messages are locked before they leave your device. The server passes them along but can't open them, not even the people who own it. Most chat apps can read everything you send.\n\nThe price of that privacy: only you hold the keys, so only you can keep them safe.",
    name: "secureExplainerKeysBody",
    desc: "Body of explainer slide 1");

String get secureExplainerTwoKeysTitle => Intl.message("Two different keys",
    name: "secureExplainerTwoKeysTitle", desc: "Title of explainer slide 2");

String get secureExplainerPassword => Intl.message("Password",
    name: "secureExplainerPassword",
    desc: "Card title in explainer slide 2 (short)");

String get secureExplainerPasswordSub =>
    Intl.message("Gets you into\nyour account",
        name: "secureExplainerPasswordSub",
        desc: "Card text under Password in explainer slide 2; two short lines");

String get secureExplainerRecoveryKey => Intl.message("Recovery key",
    name: "secureExplainerRecoveryKey",
    desc: "Card title in explainer slide 2 (short)");

String get secureExplainerRecoveryKeySub => Intl.message(
    "Unlocks your\nprivate messages",
    name: "secureExplainerRecoveryKeySub",
    desc: "Card text under Recovery key in explainer slide 2; two short lines");

String get secureExplainerTwoKeysBody => Intl.message(
    "Your password lets you sign in. Your recovery key opens your locked messages. Resetting your password does not bring back lost messages.",
    name: "secureExplainerTwoKeysBody",
    desc: "Body of explainer slide 2");

String get secureExplainerVouchTitle =>
    Intl.message("Your devices vouch for each other",
        name: "secureExplainerVouchTitle", desc: "Title of explainer slide 3");

String get secureExplainerPhone => Intl.message("Phone",
    name: "secureExplainerPhone",
    desc: "Device label in explainer slide 3 (very short)");

String get secureExplainerLaptop => Intl.message("Laptop",
    name: "secureExplainerLaptop",
    desc: "Device label in explainer slide 3 (very short)");

String get secureExplainerNewTablet => Intl.message("New tablet",
    name: "secureExplainerNewTablet",
    desc: "Device label in explainer slide 3 (very short)");

String get secureExplainerVouchBody => Intl.message(
    "Every device you approve holds your keys and can approve the next one. That's also how friends know a device is really you and not someone who stole your password.",
    name: "secureExplainerVouchBody",
    desc: "Body of explainer slide 3");

String get secureExplainerLoseTitle =>
    Intl.message("When do you lose messages?",
        name: "secureExplainerLoseTitle", desc: "Title of explainer slide 4");

String get secureExplainerLosePhone =>
    Intl.message("Lose your phone, laptop still signed in",
        name: "secureExplainerLosePhone",
        desc: "Scenario title in explainer slide 4");

String get secureExplainerLosePhoneBody =>
    Intl.message("Fine. Approve the new phone from your laptop.",
        name: "secureExplainerLosePhoneBody",
        desc: "Scenario outcome in explainer slide 4");

String get secureExplainerLoseAllWithKey =>
    Intl.message("Lose everything, have your recovery key",
        name: "secureExplainerLoseAllWithKey",
        desc: "Scenario title in explainer slide 4");

String get secureExplainerLoseAllWithKeyBody =>
    Intl.message("Fine. The key brings it all back.",
        name: "secureExplainerLoseAllWithKeyBody",
        desc: "Scenario outcome in explainer slide 4");

String get secureExplainerLoseAllNoKey =>
    Intl.message("Lose everything, no recovery key",
        name: "secureExplainerLoseAllNoKey",
        desc: "Scenario title in explainer slide 4");

String get secureExplainerLoseAllNoKeyBody =>
    Intl.message("Gone for good. Nobody can recover them.",
        name: "secureExplainerLoseAllNoKeyBody",
        desc: "Scenario outcome in explainer slide 4");

String get secureExplainerLoseBody => Intl.message(
    "That last one is the only way to lose your messages. Your recovery key is the safety net.",
    name: "secureExplainerLoseBody",
    desc: "Body of explainer slide 4");
