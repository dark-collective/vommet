import 'package:commet/ui/pages/secure_setup/secure_setup_widgets.dart';
import 'package:commet/utils/links/link_utils.dart';
import 'package:flutter/material.dart';

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
        title: "What does this mean?",
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
          SetupPrimaryButton(slide < slides.length - 1 ? "Next" : "Got it",
              onPressed: () => slide < slides.length - 1
                  ? setState(() => slide++)
                  : Navigator.of(context).pop()),
          SetupTextLink("Read the full guide",
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
        "Only you hold the keys",
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          device(Icons.smartphone, "You", true),
          arrowLock(),
          Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.dns_outlined,
                size: 52, color: t.colorScheme.onSurfaceVariant),
            const SizedBox(height: 4),
            Icon(Icons.visibility_off_outlined,
                size: 22, color: t.colorScheme.onSurfaceVariant),
            const SizedBox(height: 4),
            Text("Server",
                style: t.textTheme.bodySmall
                    ?.copyWith(color: t.colorScheme.onSurfaceVariant)),
          ]),
          arrowLock(),
          device(Icons.smartphone, "Friend", true),
        ]),
        "Messages are locked before they leave your device. The server "
            "passes them along but can't open them, not even the people who "
            "own it. Most chat apps can read everything you send.\n\n"
            "The price of that privacy: only you hold the keys, so only you "
            "can keep them safe."
      ),
      (
        "Two different keys",
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          keyCard(Icons.door_front_door_outlined, "Password",
              "Gets you into\nyour account", t.colorScheme.primary),
          keyCard(Icons.lock_outline, "Recovery key",
              "Unlocks your\nprivate messages", setupGood),
        ]),
        "Your password lets you sign in. Your recovery key opens your locked "
            "messages. Resetting your password does not bring back lost "
            "messages."
      ),
      (
        "Your devices vouch for each other",
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          device(Icons.smartphone, "Phone", true),
          vouch(),
          device(Icons.laptop, "Laptop", true),
          vouch(),
          device(Icons.tablet_android, "New tablet", false),
        ]),
        "Every device you approve holds your keys and can approve the next "
            "one. That's also how friends know a device is really you and not "
            "someone who stole your password."
      ),
      (
        "When do you lose messages?",
        Column(mainAxisSize: MainAxisSize.min, children: [
          outcome(
              Icons.check_circle,
              setupGood,
              "Lose your phone, laptop still signed in",
              "Fine. Approve the new phone from your laptop."),
          const SizedBox(height: 10),
          outcome(
              Icons.check_circle,
              setupGood,
              "Lose everything, have your recovery key",
              "Fine. The key brings it all back."),
          const SizedBox(height: 10),
          outcome(
              Icons.cancel,
              t.colorScheme.error,
              "Lose everything, no recovery key",
              "Gone for good. Nobody can recover them."),
        ]),
        "That last one is the only way to lose your messages. Your recovery "
            "key is the safety net."
      ),
    ];
  }
}
