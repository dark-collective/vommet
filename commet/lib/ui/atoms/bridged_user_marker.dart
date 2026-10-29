// Vommet issue 853: the network icon after a bridged user's name, and the
// chip on their user card (dashed while it's a guess).
import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/main.dart';
import 'package:commet/utils/bridged_users.dart';
import 'package:flutter/material.dart';

/// The network's icon; a voice bridge puppet gets the Discord logo with a
/// small green sound wave on its corner.
class BridgeNetworkIcon extends StatelessWidget {
  const BridgeNetworkIcon(this.network,
      {this.size = 14, this.color, super.key});

  final BridgeNetwork network;
  final double size;
  final Color? color;

  static const Color voiceGreen = Color(0xFF23A55A);

  @override
  Widget build(BuildContext context) {
    final color = this.color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    final icon = Icon(BridgedUsers.iconOf(network), size: size, color: color);
    if (network != BridgeNetwork.voiceBridge) return icon;
    final wave = (size * 0.6).roundToDouble();
    return SizedBox(
      width: size + wave / 3,
      height: size,
      child: Stack(clipBehavior: Clip.none, children: [
        icon,
        Positioned(
          right: 0,
          bottom: -wave / 4,
          child: Container(
            width: wave,
            height: wave,
            decoration: BoxDecoration(
              color: voiceGreen,
              shape: BoxShape.circle,
              border: Border.all(
                  color: Theme.of(context).colorScheme.surface, width: 1),
            ),
            alignment: Alignment.center,
            child: Icon(Icons.graphic_eq, size: wave - 3, color: Colors.white),
          ),
        ),
      ]),
    );
  }
}

/// Rebuilds when the settings change or a profile answer arrives.
mixin _BridgedRefresh<T extends StatefulWidget> on State<T> {
  late final List<StreamSubscription> _subs;

  String get bridgedUserId;

  @override
  void initState() {
    super.initState();
    _subs = [
      preferences.onSettingChanged.listen((_) => _refresh()),
      BridgedUsers.onChanged.listen((id) {
        if (id == bridgedUserId) _refresh();
      }),
    ];
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }
}

/// The icon after a name in the member list; nothing for everyone else.
class BridgedUserMarker extends StatefulWidget {
  const BridgedUserMarker(
      {required this.client, required this.userId, this.size = 14, super.key});

  final Client client;
  final String userId;
  final double size;

  @override
  State<BridgedUserMarker> createState() => _BridgedUserMarkerState();
}

class _BridgedUserMarkerState extends State<BridgedUserMarker>
    with _BridgedRefresh<BridgedUserMarker> {
  @override
  String get bridgedUserId => widget.userId;

  @override
  Widget build(BuildContext context) {
    final user = BridgedUsers.of(widget.client, widget.userId);
    if (user == null) return const SizedBox.shrink();
    final label = BridgedUsers.labelOf(user);
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Tooltip(
        message:
            user.isGuess ? bridgedTooltipGuess(label) : bridgedTooltip(label),
        child: BridgeNetworkIcon(user.network, size: widget.size),
      ),
    );
  }
}

/// The user card's "Probably Telegram" chip with the explanation and the
/// "Not right? Change it" menu.
class BridgedUserChip extends StatefulWidget {
  const BridgedUserChip(
      {required this.client, required this.userId, super.key});

  final Client client;
  final String userId;

  @override
  State<BridgedUserChip> createState() => _BridgedUserChipState();
}

class _BridgedUserChipState extends State<BridgedUserChip>
    with _BridgedRefresh<BridgedUserChip> {
  @override
  String get bridgedUserId => widget.userId;

  @override
  Widget build(BuildContext context) {
    if (!BridgedUsers.mark.value) return const SizedBox.shrink();
    final user = BridgedUsers.of(widget.client, widget.userId);
    final overridden = BridgedUsers.overrideMap.containsKey(widget.userId);
    // Nothing to show, unless the user said "not bridged" and may want to
    // take it back.
    if (user == null && !overridden) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final small = theme.textTheme.bodySmall?.copyWith(color: muted);

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (user != null) _chip(context, user),
          if (user != null) const SizedBox(height: 4),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                  user == null ? bridgedSettingsNotBridged : _explanation(user),
                  style: small),
              const SizedBox(width: 6),
              _changeMenu(context, user),
            ],
          ),
        ],
      ),
    );
  }

  String _explanation(BridgedUser user) {
    final label = BridgedUsers.labelOf(user);
    switch (user.source) {
      case BridgeSource.guessed:
        return bridgedGuessExplained(BridgedUsers.bridgeName(user.network));
      case BridgeSource.declared:
        return bridgedDeclaredExplained(label);
      case BridgeSource.yours:
        return bridgedYoursExplained(label);
    }
  }

  Widget _chip(BuildContext context, BridgedUser user) {
    final scheme = Theme.of(context).colorScheme;
    final label = BridgedUsers.labelOf(user);
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(6, 2, 8, 2),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        BridgeNetworkIcon(user.network, size: 14, color: scheme.primary),
        const SizedBox(width: 6),
        Text(user.isGuess ? bridgedChipGuess(label) : label,
            style: Theme.of(context)
                .textTheme
                .labelMedium
                ?.copyWith(color: scheme.onSurface)),
      ]),
    );
    if (user.isGuess) {
      return CustomPaint(
        painter: _DashedBorder(scheme.outline),
        child: content,
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        border: Border.all(color: scheme.outline),
        borderRadius: BorderRadius.circular(6),
      ),
      child: content,
    );
  }

  Widget _changeMenu(BuildContext context, BridgedUser? user) {
    final overrides = BridgedUsers.overrideMap;
    final current = overrides[widget.userId];
    final guess = BridgedUsers.guessWithoutOverride(widget.userId);

    return MenuAnchor(
      menuChildren: [
        if (guess != null)
          MenuItemButton(
            leadingIcon: Icon(current == null ? Icons.check : null, size: 18),
            onPressed: () => BridgedUsers.setOverride(widget.userId, null),
            child:
                Text(bridgedUseGuess(BridgedUsers.builtInLabel(guess.network))),
          ),
        MenuItemButton(
          leadingIcon: Icon(
              (current == notBridgedOverride ||
                      (current == null && guess == null))
                  ? Icons.check
                  : null,
              size: 18),
          onPressed: () =>
              BridgedUsers.setOverride(widget.userId, notBridgedOverride),
          child: Text(bridgedSettingsNotBridged),
        ),
        SubmenuButton(
          leadingIcon: const Icon(Icons.swap_horiz, size: 18),
          menuChildren: [
            for (final network
                in BridgeNetwork.values.where((n) => n != BridgeNetwork.other))
              MenuItemButton(
                leadingIcon: SizedBox(
                    width: 20, child: BridgeNetworkIcon(network, size: 16)),
                trailingIcon: current == network.name
                    ? const Icon(Icons.check, size: 18)
                    : null,
                onPressed: () =>
                    BridgedUsers.setOverride(widget.userId, network.name),
                child: Text(BridgedUsers.builtInLabel(network)),
              ),
          ],
          child: Text(bridgedChooseNetwork),
        ),
      ],
      builder: (context, controller, _) => InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: () => controller.isOpen ? controller.close() : controller.open(),
        child: Text(
          bridgedChangeIt,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              decoration: TextDecoration.underline),
        ),
      ),
    );
  }
}

class _DashedBorder extends CustomPainter {
  _DashedBorder(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(
          Offset.zero & size, const Radius.circular(6)));
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(metric.extractPath(distance, distance + 4), paint);
        distance += 7;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder oldDelegate) => oldDelegate.color != color;
}
