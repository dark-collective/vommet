import 'package:flutter/material.dart';

/// Vommet (New room info page): the building blocks of the Room info page,
/// shared by the phone page, the desktop dialog and the space page.

/// A section heading in capitals, with an optional caption on the right
/// ("Only you see these.").
class InfoSectionHeader extends StatelessWidget {
  const InfoSectionHeader(this.title,
      {this.caption, this.icon, this.trailing, super.key});
  final String title;
  final String? caption;
  final IconData? icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 8),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 15, color: scheme.onSurfaceVariant),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(title.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                    color: scheme.onSurfaceVariant)),
          ),
          const Spacer(),
          if (caption != null)
            Flexible(
              flex: 2,
              child: Text(caption!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: text.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant.withAlpha(170))),
            ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// A rounded card holding rows, with dividers between them.
class InfoGroup extends StatelessWidget {
  const InfoGroup(this.children, {super.key});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rows = children;
    if (rows.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(14)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0)
              Divider(
                  height: 1,
                  thickness: 1,
                  indent: 52,
                  color: scheme.onSurface.withAlpha(22)),
            rows[i],
          ],
        ],
      ),
    );
  }
}

/// One row: icon, title (+ subtitle), its current value on the right, and a
/// chevron. [locked] adds a lock: the user can look but not change it.
class InfoRow extends StatelessWidget {
  const InfoRow({
    required this.icon,
    required this.title,
    this.subtitle,
    this.value,
    this.valueColor,
    this.trailing,
    this.onTap,
    this.onLongPress,
    this.locked = false,
    this.danger = false,
    this.chevron = true,
    super.key,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? value;
  final Color? valueColor;
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool locked;
  final bool danger;
  final bool chevron;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final color = danger ? scheme.error : scheme.onSurface;
    final faint = scheme.onSurfaceVariant.withAlpha(150);
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      mouseCursor:
          onTap == null ? MouseCursor.defer : WidgetStateMouseCursor.clickable,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Row(
          children: [
            Icon(icon,
                size: 21,
                color: danger ? scheme.error : scheme.onSurfaceVariant),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: text.bodyMedium?.copyWith(
                          color: color,
                          fontWeight:
                              danger ? FontWeight.w600 : FontWeight.w500)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!,
                        style: text.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant)),
                  ],
                ],
              ),
            ),
            if (value != null) ...[
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 170),
                child: Text(value!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: text.bodySmall?.copyWith(
                        color: valueColor ?? scheme.onSurfaceVariant)),
              ),
            ],
            if (trailing != null) ...[const SizedBox(width: 8), trailing!],
            if (locked) ...[
              const SizedBox(width: 6),
              Tooltip(
                  message: "Needs a higher role to change",
                  child: Icon(Icons.lock_outline, size: 15, color: faint)),
            ],
            if (chevron && !danger && onTap != null) ...[
              const SizedBox(width: 2),
              Icon(Icons.chevron_right, size: 20, color: faint),
            ],
          ],
        ),
      ),
    );
  }
}

/// A row with a switch instead of a chevron.
class InfoSwitchRow extends StatelessWidget {
  const InfoSwitchRow({
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    super.key,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return InfoRow(
      icon: icon,
      title: title,
      subtitle: subtitle,
      chevron: false,
      onTap: onChanged == null ? null : () => onChanged!(!value),
      trailing: Switch(value: value, onChanged: onChanged),
    );
  }
}

/// A round quick action under the header (Mute, Search, Invite, Call).
class InfoQuickAction extends StatelessWidget {
  const InfoQuickAction({
    required this.icon,
    required this.label,
    this.sublabel,
    this.onTap,
    this.onLongPress,
    this.active = false,
    super.key,
  });

  final IconData icon;
  final String label;
  final String? sublabel;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final enabled = onTap != null;
    final fg = !enabled
        ? scheme.onSurface.withAlpha(90)
        : active
            ? scheme.primary
            : scheme.onSurface;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Material(
          color: active
              ? scheme.primary.withAlpha(40)
              : scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(14),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            onLongPress: onLongPress,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 22, color: fg),
                  const SizedBox(height: 5),
                  Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.labelMedium
                          ?.copyWith(fontWeight: FontWeight.w600, color: fg)),
                  if (sublabel != null)
                    Text(sublabel!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.labelSmall
                            ?.copyWith(color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A small caption under a group.
class InfoCaption extends StatelessWidget {
  const InfoCaption(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
      child: Text(text,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: scheme.onSurfaceVariant.withAlpha(170))),
    );
  }
}

/// A sub-page opened from a row: a title bar naming the row and whose
/// setting it is ("Pixel Art Club · just for you"), then the page.
class InfoSubPage extends StatelessWidget {
  const InfoSubPage({
    required this.title,
    required this.child,
    this.subtitle,
    this.scrollable = true,
    this.actions = const [],
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final bool scrollable;
  final List<Widget> actions;

  /// Opens [page] over the current one.
  static Future<void> open(BuildContext context, Widget page) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        backgroundColor: scheme.surface,
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            if (subtitle != null)
              Text(subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          ],
        ),
        actions: actions,
      ),
      body: SafeArea(
        top: false,
        child: scrollable
            ? SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 24), child: child)
            : child,
      ),
    );
  }
}
