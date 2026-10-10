import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Vommet issue 129: the visual pieces of the secure messaging setup, as in
/// the approved renders (unit_test/secure_setup_mockup_test.dart in the
/// mockup harness).
const setupWarn = Color(0xffffb74d);
const setupGood = Color(0xff81c784);

class SetupSteps extends StatelessWidget {
  const SetupSteps(this.at, {this.of = 4, super.key});
  final int at;
  final int of;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      for (var i = 0; i < of; i++)
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: i == at ? 22 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: i <= at ? scheme.primary : scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
    ]);
  }
}

/// A full setup screen: top bar (back, title, help), optional step dots, a
/// scrolling body and buttons pinned at the bottom. Phone-width centred on
/// desktop.
class SetupPage extends StatelessWidget {
  const SetupPage({
    required this.children,
    this.bottom = const [],
    this.onBack,
    this.onHelp,
    this.title,
    this.step,
    super.key,
  });

  final List<Widget> children;
  final List<Widget> bottom;
  final VoidCallback? onBack;
  final VoidCallback? onHelp;
  final String? title;
  final int? step;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(children: [
            SizedBox(
              height: 52,
              child: Row(children: [
                SizedBox(
                    width: 52,
                    child: onBack == null
                        ? null
                        : IconButton(
                            tooltip: "Back",
                            icon: const Icon(Icons.arrow_back),
                            onPressed: onBack)),
                Expanded(
                  child: Center(
                    child: Text(title ?? "",
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(color: scheme.onSurfaceVariant)),
                  ),
                ),
                SizedBox(
                    width: 52,
                    child: onHelp == null
                        ? null
                        : IconButton(
                            tooltip: "What does this mean?",
                            icon: Icon(Icons.help_outline,
                                color: scheme.onSurfaceVariant),
                            onPressed: onHelp)),
              ]),
            ),
            if (step != null) ...[SetupSteps(step!), const SizedBox(height: 8)],
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: children),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 18),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: bottom),
            ),
          ]),
        ),
      ),
    );
  }
}

/// A dialog in the secure setup's style: icon, title, content and
/// full-width buttons, at most 420 wide. A plain [Dialog], not an
/// AlertDialog: AlertDialog measures its children's natural width, which
/// full-width buttons don't have (a layout assertion on desktop).
class SetupDialog extends StatelessWidget {
  const SetupDialog(
      {super.key,
      this.icon,
      required this.title,
      required this.content,
      required this.buttons});

  final Widget? icon;
  final String title;
  final Widget content;
  final List<Widget> buttons;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (icon != null) ...[
                Center(child: icon),
                const SizedBox(height: 16)
              ],
              Text(title,
                  textAlign: TextAlign.center,
                  style: t.textTheme.headlineSmall),
              const SizedBox(height: 16),
              DefaultTextStyle.merge(
                  style: t.textTheme.bodyMedium
                      ?.copyWith(color: t.colorScheme.onSurfaceVariant),
                  child: content),
              const SizedBox(height: 24),
              ...buttons,
            ],
          ),
        ),
      ),
    );
  }
}

class SetupPrimaryButton extends StatelessWidget {
  const SetupPrimaryButton(this.label,
      {this.onPressed, this.icon, this.busy = false, super.key});
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: FilledButton(
        onPressed: busy ? null : onPressed,
        style: FilledButton.styleFrom(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14))),
        child: busy
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5))
            : Row(mainAxisSize: MainAxisSize.min, children: [
                if (icon != null) ...[Icon(icon), const SizedBox(width: 8)],
                // Shrinks rather than overflows on narrow screens and with
                // large text settings (the button's height is fixed).
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(label,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                ),
              ]),
      ),
    );
  }
}

class SetupTextLink extends StatelessWidget {
  const SetupTextLink(this.label, {this.onTap, this.color, super.key});
  final String label;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TextButton(
      onPressed: onTap,
      child: Text(label,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: color ?? scheme.onSurfaceVariant,
              decoration: TextDecoration.underline)),
    );
  }
}

class SetupTitle extends StatelessWidget {
  const SetupTitle(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Text(text,
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.onSurface));
}

class SetupBody extends StatelessWidget {
  const SetupBody(this.text, {this.align = TextAlign.center, super.key});
  final String text;
  final TextAlign align;

  @override
  Widget build(BuildContext context) => Text(text,
      textAlign: align,
      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant, height: 1.35));
}

class SetupBubbleIcon extends StatelessWidget {
  const SetupBubbleIcon(this.icon, {this.color, this.size = 34, super.key});
  final IconData icon;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final col = color ?? Theme.of(context).colorScheme.primary;
    return Center(
      child: Container(
        width: size * 2,
        height: size * 2,
        decoration: BoxDecoration(
            color: col.withValues(alpha: 0.16), shape: BoxShape.circle),
        child: Icon(icon, size: size, color: col),
      ),
    );
  }
}

class SetupCallout extends StatelessWidget {
  const SetupCallout(this.icon, this.color, this.title, this.body,
      {this.trailing, super.key});
  final IconData icon;
  final Color color;
  final String title;
  final String body;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        border: Border.all(color: color.withValues(alpha: 0.55)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(width: 10),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: t.textTheme.titleSmall?.copyWith(
                    color: t.colorScheme.onSurface,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(body,
                style: t.textTheme.bodyMedium?.copyWith(
                    color: t.colorScheme.onSurfaceVariant, height: 1.3)),
          ]),
        ),
        if (trailing != null) trailing!,
      ]),
    );
  }
}

class SetupOption extends StatelessWidget {
  const SetupOption(this.icon, this.title, this.subtitle,
      {this.badge,
      this.badgeColor = setupGood,
      this.selected = false,
      this.onTap,
      super.key});
  final IconData icon;
  final String title;
  final String subtitle;
  final String? badge;
  final Color badgeColor;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: t.colorScheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
              color: selected ? t.colorScheme.primary : Colors.transparent,
              width: 2),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
            child: Row(children: [
              Icon(icon,
                  size: 28,
                  color: selected
                      ? t.colorScheme.primary
                      : t.colorScheme.onSurface),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            Text(title,
                                style: t.textTheme.titleMedium?.copyWith(
                                    color: t.colorScheme.onSurface,
                                    fontWeight: FontWeight.w600)),
                            if (badge != null)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                    color: badgeColor.withValues(alpha: 0.18),
                                    borderRadius: BorderRadius.circular(6)),
                                child: Text(badge!,
                                    style: t.textTheme.labelSmall?.copyWith(
                                        color: badgeColor,
                                        fontWeight: FontWeight.w700)),
                              ),
                          ]),
                      const SizedBox(height: 3),
                      Text(subtitle,
                          style: t.textTheme.bodyMedium?.copyWith(
                              color: t.colorScheme.onSurfaceVariant,
                              height: 1.3)),
                    ]),
              ),
              Icon(Icons.chevron_right, color: t.colorScheme.onSurfaceVariant),
            ]),
          ),
        ),
      ),
    );
  }
}

class SetupBullet extends StatelessWidget {
  const SetupBullet(this.text,
      {this.icon = Icons.close, this.color, super.key});
  final String text;
  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: 20, color: color ?? t.colorScheme.error),
        ),
        const SizedBox(width: 10),
        Expanded(
            child: Text(text,
                style: t.textTheme.bodyLarge
                    ?.copyWith(color: t.colorScheme.onSurface, height: 1.35))),
      ]),
    );
  }
}

/// A button that only acts after being held for [duration], filling up as
/// it's held (for skipping setup or starting over).
class HoldButton extends StatefulWidget {
  const HoldButton(this.label,
      {required this.onHeld,
      this.duration = const Duration(seconds: 2),
      super.key});
  final String label;
  final VoidCallback onHeld;
  final Duration duration;

  @override
  State<HoldButton> createState() => _HoldButtonState();
}

class _HoldButtonState extends State<HoldButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: widget.duration)
        ..addStatusListener((status) {
          if (status == AnimationStatus.completed) {
            HapticFeedback.heavyImpact();
            widget.onHeld();
            _controller.reset();
          }
        });

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _start() {
    HapticFeedback.selectionClick();
    _controller.forward();
  }

  void _stop() {
    if (_controller.status != AnimationStatus.completed) {
      _controller.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final error = t.colorScheme.error;
    return Semantics(
      button: true,
      label: "${widget.label}. Press and hold.",
      child: GestureDetector(
        onTapDown: (_) => _start(),
        onTapUp: (_) => _stop(),
        onTapCancel: _stop,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            height: 48,
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) => Stack(children: [
                Positioned.fill(
                    child: Container(
                        decoration: BoxDecoration(
                            border:
                                Border.all(color: error.withValues(alpha: 0.7)),
                            borderRadius: BorderRadius.circular(14)))),
                FractionallySizedBox(
                    widthFactor: _controller.value,
                    child: Container(color: error.withValues(alpha: 0.30))),
                Center(
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.touch_app_outlined, color: error, size: 20),
                    const SizedBox(width: 8),
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(widget.label,
                            style: t.textTheme.titleSmall?.copyWith(
                                color: error, fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// A recovery key shown in groups of 4, for reading and copying out.
class RecoveryKeyText extends StatelessWidget {
  const RecoveryKeyText(this.recoveryKey, {this.label, super.key});
  final String recoveryKey;
  final String? label;

  static List<String> groups(String key) => key
          .replaceAll(RegExp(r"\s"), "")
          .split("")
          .fold<List<String>>([], (acc, ch) {
        if (acc.isEmpty || acc.last.length == 4) acc.add("");
        acc[acc.length - 1] += ch;
        return acc;
      });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: t.colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (label != null) ...[
          Text(label!,
              style: t.textTheme.labelMedium
                  ?.copyWith(color: t.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 8),
        ],
        SelectableText(groups(recoveryKey).join(" "),
            style: t.textTheme.titleLarge?.copyWith(
                fontFamily: "monospace",
                fontWeight: FontWeight.w700,
                height: 1.5,
                letterSpacing: 1)),
      ]),
    );
  }
}

/// Keeps screenshots blocked while [child] is on screen (Android).
class ScreenshotGuard extends StatefulWidget {
  const ScreenshotGuard(
      {required this.child, required this.setSecure, super.key});
  final Widget child;
  final Future<void> Function(bool on) setSecure;

  @override
  State<ScreenshotGuard> createState() => _ScreenshotGuardState();
}

class _ScreenshotGuardState extends State<ScreenshotGuard> {
  @override
  void initState() {
    super.initState();
    unawaited(widget.setSecure(true));
  }

  @override
  void dispose() {
    unawaited(widget.setSecure(false));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
