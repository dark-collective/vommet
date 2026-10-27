import 'package:commet/client/client.dart';
import 'package:commet/client/components/command/command_component.dart';
import 'package:commet/config/layout_config.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Vommet: one effect in the "Send with effect" picker. Picking it sends
/// `/<command> <text>`, so it goes through the same command as typing it.
class MessageEffectOption {
  const MessageEffectOption(this.command, this.emoji, this.label);

  final String command;

  /// Shown in the picker, and sent as the body when nothing was typed.
  final String emoji;
  final String Function() label;

  String commandText(String text) => "/$command $text".trim();
}

/// Vommet: the effect picker on the Send button — long-press or right-click
/// it with something typed, or tap it with nothing typed.
class MessageEffectPicker {
  static String get labelSendWithEffect => Intl.message("Send with effect",
      desc: "Title of the menu on the send button that sends a message with "
          "a full-screen effect, like confetti",
      name: "labelSendWithEffect");

  static String get labelEffectConfetti => Intl.message("Confetti",
      desc: "Message effect: confetti", name: "labelEffectConfetti");

  static String get labelEffectFireworks => Intl.message("Fireworks",
      desc: "Message effect: fireworks", name: "labelEffectFireworks");

  static String get labelEffectHearts => Intl.message("Hearts",
      desc: "Message effect: hearts floating up", name: "labelEffectHearts");

  static String get labelEffectSnowfall => Intl.message("Snowfall",
      desc: "Message effect: falling snow", name: "labelEffectSnowfall");

  static String get labelEffectRainfall => Intl.message("Rainfall",
      desc: "Message effect: falling rain", name: "labelEffectRainfall");

  static String get labelEffectSpaceInvaders => Intl.message("Space invaders",
      desc: "Message effect: space invaders marching down the screen",
      name: "labelEffectSpaceInvaders");

  static String get labelEffectHug => Intl.message("Hug",
      desc: "Message effect: a hug", name: "labelEffectHug");

  static String get labelEffectCuddle => Intl.message("Cuddle",
      desc: "Message effect: a cuddle", name: "labelEffectCuddle");

  static String get labelEffectGooglyEyes => Intl.message("Googly eyes",
      desc: "Message effect: googly eyes", name: "labelEffectGooglyEyes");

  static final List<MessageEffectOption> all = [
    MessageEffectOption("confetti", "🎉", () => labelEffectConfetti),
    MessageEffectOption("fireworks", "🎆", () => labelEffectFireworks),
    MessageEffectOption("hearts", "💝", () => labelEffectHearts),
    MessageEffectOption("snowfall", "❄️", () => labelEffectSnowfall),
    MessageEffectOption("rainfall", "🌧️", () => labelEffectRainfall),
    MessageEffectOption("spaceinvaders", "👾", () => labelEffectSpaceInvaders),
    MessageEffectOption("hug", "🤗", () => labelEffectHug),
    MessageEffectOption("cuddle", "😊", () => labelEffectCuddle),
    MessageEffectOption("googly", "👀", () => labelEffectGooglyEyes),
  ];

  /// The effects [client] can send (its commands include them).
  static List<MessageEffectOption> available(Client? client) {
    final commands =
        client?.getComponent<CommandComponent>()?.getCommands().toSet();
    if (commands == null) return const [];
    return all.where((e) => commands.contains(e.command)).toList();
  }

  /// Menu items for [AdaptiveContextMenu]: a list on desktop, a grid in the
  /// phone sheet.
  static List<tiamat.ContextMenuItem> menuItems(
    BuildContext context, {
    required List<MessageEffectOption> options,
    required void Function(MessageEffectOption option) onPick,
  }) {
    if (options.isEmpty) return const [];

    if (!MediaQuery.of(context).desktop) {
      return [
        tiamat.ContextMenuItem(
          text: labelSendWithEffect,
          customBuilder: (context, onClicked, {closeMenu}) => EffectGrid(
            options: options,
            onPick: (option) {
              closeMenu?.call();
              onPick(option);
            },
          ),
        ),
      ];
    }

    return [
      tiamat.ContextMenuItem(
        text: labelSendWithEffect,
        customBuilder: (context, onClicked, {closeMenu}) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 2),
          child: tiamat.Text.labelLow(labelSendWithEffect.toUpperCase()),
        ),
      ),
      for (final option in options)
        tiamat.ContextMenuItem(
          text: option.label(),
          onPressed: () => onPick(option),
          customBuilder: (context, onClicked, {closeMenu}) => Padding(
            padding: const EdgeInsets.all(4.0),
            child: InkWell(
              key: ValueKey("effect-${option.command}"),
              onTap: onClicked,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Row(
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    SizedBox(
                        width: 28,
                        child: Text(option.emoji,
                            style: const TextStyle(fontSize: 18))),
                    tiamat.Text(option.label(),
                        type: tiamat.TextType.body,
                        maxLines: 1,
                        color: Theme.of(context).colorScheme.onSurface),
                  ],
                ),
              ),
            ),
          ),
        ),
    ];
  }
}

/// The phone picker: big emoji tiles, three to a row.
class EffectGrid extends StatelessWidget {
  const EffectGrid({required this.options, required this.onPick, super.key});

  final List<MessageEffectOption> options;
  final void Function(MessageEffectOption option) onPick;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
          child: tiamat.Text.labelEmphasised(
              MessageEffectPicker.labelSendWithEffect),
        ),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 1.25,
          children: [
            for (final option in options)
              Material(
                color: scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  key: ValueKey("effect-${option.command}"),
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => onPick(option),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(option.emoji, style: const TextStyle(fontSize: 28)),
                      const SizedBox(height: 4),
                      tiamat.Text.labelLow(option.label()),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
