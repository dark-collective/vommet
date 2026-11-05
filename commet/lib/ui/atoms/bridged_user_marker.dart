// Vommet issue 853: the network icon after a bridged user's name, and the
// chip on their user card. Network marks: solid when the person's server is
// a trusted bridge server, dashed when their ID only looks bridged, and a
// drawn [m] for people who aren't bridged.
import 'dart:async';
import 'dart:math' as math;

import 'package:commet/client/client.dart';
import 'package:commet/ui/atoms/redaction_scope.dart';
import 'package:commet/ui/pages/settings/categories/app/bridged_users_settings_page.dart';
import 'package:commet/utils/bridged_users.dart';
import 'package:flutter/material.dart';

/// The network's icon; a voice bridge puppet gets the plain Discord logo,
/// like anyone from Discord.
class BridgeNetworkIcon extends StatelessWidget {
  const BridgeNetworkIcon(this.network,
      {this.size = 14, this.color, super.key});

  final BridgeNetwork network;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final color = this.color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return Icon(BridgedUsers.iconOf(network), size: size, color: color);
  }
}

/// A network whose bridge isn't verified: the network's glyph, smaller,
/// in a dashed circle.
class UnverifiedNetworkIcon extends StatelessWidget {
  const UnverifiedNetworkIcon(this.network,
      {this.size = 14, this.color, super.key});

  final BridgeNetwork network;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final color = this.color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _DashedCircle(color),
        child: Center(
          child: Icon(BridgedUsers.iconOf(network),
              size: size * 0.55, color: color.withValues(alpha: 0.8)),
        ),
      ),
    );
  }
}

/// The "[m]" glyph after someone who isn't bridged: drawn brackets around an
/// "m", not the Matrix logo.
class MatrixMark extends StatelessWidget {
  const MatrixMark({this.size = 14, this.color, super.key});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final color = this.color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return SizedBox(
      width: size * 1.25,
      height: size,
      child: CustomPaint(
        painter: _MatrixPainter(color),
        child: Center(
          child: Text("m",
              textScaler: TextScaler.noScaling,
              style: TextStyle(
                  fontSize: size * 0.78,
                  fontWeight: FontWeight.w700,
                  height: 1.0,
                  color: color)),
        ),
      ),
    );
  }
}

class _MatrixPainter extends CustomPainter {
  _MatrixPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.2, size.height / 10);
    final arm = size.width * 0.16;
    final top = size.height * 0.08, bottom = size.height * 0.92;
    canvas.drawPath(
        Path()
          ..moveTo(arm, top)
          ..lineTo(1, top)
          ..lineTo(1, bottom)
          ..lineTo(arm, bottom),
        paint);
    canvas.drawPath(
        Path()
          ..moveTo(size.width - arm, top)
          ..lineTo(size.width - 1, top)
          ..lineTo(size.width - 1, bottom)
          ..lineTo(size.width - arm, bottom),
        paint);
  }

  @override
  bool shouldRepaint(_MatrixPainter oldDelegate) => oldDelegate.color != color;
}

class _DashedCircle extends CustomPainter {
  _DashedCircle(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final rect = Rect.fromCircle(
        center: size.center(Offset.zero), radius: size.width / 2 - 0.6);
    const dashes = 8;
    for (var i = 0; i < dashes; i++) {
      canvas.drawArc(
          rect, i * 2 * math.pi / dashes, math.pi / dashes * 0.9, false, paint);
    }
  }

  @override
  bool shouldRepaint(_DashedCircle oldDelegate) => oldDelegate.color != color;
}

/// Rebuilds when the settings change, a profile answer arrives or a room's
/// bridges change.
mixin _BridgedRefresh<T extends StatefulWidget> on State<T> {
  late final List<StreamSubscription> _subs;

  @override
  void initState() {
    super.initState();
    _subs = [BridgedUsers.onAnyChange.listen((_) => _refresh())];
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

/// The icon after a name in the member list and on messages: the network's
/// (dashed when not verified), or the [MatrixMark] where the settings show
/// it.
class BridgedUserMarker extends StatefulWidget {
  const BridgedUserMarker(
      {required this.client,
      required this.userId,
      this.room,
      this.size = 14,
      this.inCall = false,
      super.key});

  final Client client;
  final String userId;

  /// In a call's participant list or tiles: no [MatrixMark] unless the
  /// setting says everywhere (calls are short lists).
  final bool inCall;

  /// Where the person is shown: its bridges count, and it decides whether
  /// the [MatrixMark] shows.
  final Room? room;
  final double size;

  @override
  State<BridgedUserMarker> createState() => _BridgedUserMarkerState();
}

class _BridgedUserMarkerState extends State<BridgedUserMarker>
    with _BridgedRefresh<BridgedUserMarker> {
  @override
  Widget build(BuildContext context) {
    if (!BridgedUsers.mark.value) return const SizedBox.shrink();
    // A network next to a hidden name gives away who it is.
    if (RedactionScope.of(context).redactsNames) {
      return const SizedBox.shrink();
    }
    final user = BridgedUsers.of(widget.client, widget.userId,
        room: widget.room, ignoreSetting: true);
    if (user == null) {
      if (!BridgedUsers.showMatrixMark(widget.client, widget.room) ||
          (widget.inCall &&
              BridgedUsers.matrixMarkMode != MatrixMarkMode.everywhere)) {
        return const SizedBox.shrink();
      }
      return Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Tooltip(
          message: bridgedTooltipMatrix,
          child: MatrixMark(size: widget.size),
        ),
      );
    }
    if (BridgedUsers.isHidden(user)) return const SizedBox.shrink();
    final label = BridgedUsers.labelOf(user);
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Tooltip(
        message: user.verified
            ? bridgedTooltip(label)
            : bridgedTooltipUnverified(label),
        child: user.verified
            ? BridgeNetworkIcon(user.network, size: widget.size)
            : UnverifiedNetworkIcon(user.network, size: widget.size),
      ),
    );
  }
}

/// The user card's network chip (dashed "Looks like Telegram · not
/// verified" when their server isn't trusted) with the explanation and the
/// "Not right? Change it" menu.
class BridgedUserChip extends StatefulWidget {
  const BridgedUserChip(
      {required this.client,
      required this.userId,
      this.room,
      this.name,
      super.key});

  final Client client;
  final String userId;

  /// Their display name, for the voice bridge's "is in the call" line.
  final String? name;

  /// The room the card was opened from: its bridges count.
  final Room? room;

  @override
  State<BridgedUserChip> createState() => _BridgedUserChipState();
}

class _BridgedUserChipState extends State<BridgedUserChip>
    with _BridgedRefresh<BridgedUserChip> {
  @override
  Widget build(BuildContext context) {
    if (!BridgedUsers.mark.value) return const SizedBox.shrink();
    final user =
        BridgedUsers.of(widget.client, widget.userId, room: widget.room);
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
              if (user != null && !user.verified && user.server != null) ...[
                _link(
                    context,
                    bridgedTrustServer,
                    () => showAddTrustedServerDialog(context,
                        server: user.server, network: user.network)),
                const SizedBox(width: 6),
              ],
              _changeMenu(context, user),
            ],
          ),
        ],
      ),
    );
  }

  String _explanation(BridgedUser user) {
    final label = BridgedUsers.labelOf(user);
    final server = user.server ?? "";
    if (BridgedUsers.overrideMap.containsKey(widget.userId)) {
      return bridgedYoursExplained(label);
    }
    if (user.network == BridgeNetwork.voiceBridge) {
      return bridgedVoiceOnlyExplained(widget.name ?? widget.userId);
    }
    return user.verified
        ? bridgedVerifiedExplained(label, server)
        : bridgedUnverifiedExplained(label, server);
  }

  Widget _link(BuildContext context, String text, VoidCallback onTap) =>
      InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: onTap,
        child: Text(
          text,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              decoration: TextDecoration.underline),
        ),
      );

  Widget _chip(BuildContext context, BridgedUser user) {
    final scheme = Theme.of(context).colorScheme;
    final label = BridgedUsers.labelOf(user);
    final voice = user.network == BridgeNetwork.voiceBridge;
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(6, 2, 8, 2),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        user.verified
            ? BridgeNetworkIcon(user.network, size: 14, color: scheme.primary)
            : UnverifiedNetworkIcon(user.network,
                size: 14, color: scheme.primary),
        const SizedBox(width: 6),
        Text(
            voice
                ? bridgedVoiceOnlyChip
                : user.verified
                    ? label
                    : bridgedChipUnverified(label),
            style: Theme.of(context)
                .textTheme
                .labelMedium
                ?.copyWith(color: scheme.onSurface)),
      ]),
    );
    if (!user.verified) {
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
      builder: (context, controller, _) => _link(context, bridgedChangeIt,
          () => controller.isOpen ? controller.close() : controller.open()),
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
