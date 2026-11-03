import 'package:commet/client/client.dart';
import 'package:commet/client/components/command/command_component.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Vommet: one message effect (the + sheet's "Effect"). The message goes
/// out as `/<command> <text>`, through the same command as typing it.
class MessageEffectOption {
  const MessageEffectOption(this.command, this.emoji, this.label);

  final String command;

  /// Shown in the picker, and sent as the body when nothing was typed.
  final String emoji;
  final String Function() label;

  String commandText(String text) => "/$command $text".trim();
}

/// Vommet: the message effects, picked under "Effect" in the composer's +
/// for the next message.
class MessageEffectPicker {
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
}

/// The effects in the + sheet's THIS MESSAGE part, opened in place under
/// "Effect": two rows of emoji tiles. Picking one sets it for the next
/// message; picking it again drops it.
class EffectGrid extends StatelessWidget {
  const EffectGrid(
      {required this.options, required this.onPick, this.selected, super.key});

  final List<MessageEffectOption> options;
  final MessageEffectOption? selected;
  final void Function(MessageEffectOption option) onPick;

  static const int perRow = 5;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rows = [
      for (var i = 0; i < options.length; i += perRow)
        options.sublist(i, (i + perRow).clamp(0, options.length))
    ];
    return Padding(
      key: const ValueKey("effect-grid"),
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  for (final option in row)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Tooltip(
                        message: option.label(),
                        child: Material(
                          color: option.command == selected?.command
                              ? scheme.primary.withAlpha(60)
                              : scheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                          child: InkWell(
                            key: ValueKey("effect-${option.command}"),
                            borderRadius: BorderRadius.circular(8),
                            onTap: () => onPick(option),
                            child: SizedBox(
                              width: 40,
                              height: 34,
                              child: Center(
                                  child: Text(option.emoji,
                                      style: const TextStyle(fontSize: 18))),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
