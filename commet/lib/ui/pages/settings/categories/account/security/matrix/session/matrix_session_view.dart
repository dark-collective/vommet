import 'package:commet/config/layout_config.dart';
import 'package:commet/ui/atoms/adaptive_context_menu.dart';
import 'package:commet/ui/atoms/tiny_pill.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// What this device knows about a session's encryption keys.
enum SessionKeysState { loading, missing, known }

/// Vommet: when a session was last used, in words ("Active 2 hours ago",
/// "Yesterday", "Mar 2, 2026").
String sessionLastSeenLabel(int? lastSeenTimestamp, DateTime now,
    {bool isThisDevice = false}) {
  if (isThisDevice) return "Active now";
  if (lastSeenTimestamp == null) return "Never used";
  final seen = DateTime.fromMillisecondsSinceEpoch(lastSeenTimestamp);
  final ago = now.difference(seen);
  if (ago.inMinutes < 10) return "Active now";
  if (ago.inMinutes < 60) return "Active ${ago.inMinutes} minutes ago";
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(seen.year, seen.month, seen.day);
  final days = today.difference(day).inDays;
  if (days <= 0) {
    final hours = ago.inHours;
    return hours == 1 ? "Active an hour ago" : "Active $hours hours ago";
  }
  if (days == 1) return "Yesterday";
  if (days < 7) return DateFormat.EEEE().format(seen);
  return DateFormat.yMMMd().format(seen);
}

class MatrixSessionView extends StatelessWidget {
  const MatrixSessionView(
      {this.displayName,
      required this.deviceId,
      this.lastSeenIp,
      this.lastSeenTimestamp,
      super.key,
      this.verified = false,
      this.keysState = SessionKeysState.known,
      this.isThisDevice = false,
      this.inactive = false,
      this.beginVerification,
      this.removeSession,
      this.editing = false,
      this.startRename,
      this.rename,
      this.cancelRename,
      this.now});

  final String? displayName;
  final String deviceId;
  final String? lastSeenIp;
  final int? lastSeenTimestamp;
  final bool verified;

  /// Whether this device knows the session's encryption keys. Without them
  /// (the session never uploaded any) there is nothing to verify against;
  /// while the device list is still loading we can't tell yet.
  final SessionKeysState keysState;
  final bool isThisDevice;
  final bool inactive;
  final Function? beginVerification;
  final Function? removeSession;

  /// Vommet: renaming the session in place.
  final bool editing;
  final VoidCallback? startRename;
  final Future<void> Function(String name)? rename;
  final VoidCallback? cancelRename;

  /// The time "last seen" is measured from; tests pass a fixed one.
  final DateTime? now;

  String get promptMatrixVerifySession => Intl.message("Verify",
      desc: "Text on the button to verify a session",
      name: "promptMatrixVerifySession");

  String get labelMatrixSessionCannotVerify => Intl.message("Can't verify",
      desc:
          "Shown instead of the verify button for a session whose encryption keys are unknown",
      name: "labelMatrixSessionCannotVerify");

  String get labelMatrixSessionCannotVerifyExplanation => Intl.message(
      "This session hasn't shared its encryption keys, so it can't be verified. Sessions that don't support encryption (some bots and older sign-ins) never do.",
      desc:
          "Explains why a session whose encryption keys are unknown can't be verified",
      name: "labelMatrixSessionCannotVerifyExplanation");

  bool get canVerify => !verified && keysState == SessionKeysState.known;

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.of(context);
    final desktop = MediaQuery.of(context).desktop;
    final row = Row(
      spacing: 12,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10)),
          child: Icon(getIcon(), size: 22, color: scheme.onSurface),
        ),
        Expanded(
          child: editing
              ? _RenameField(
                  initial: displayName ?? "",
                  rename: rename,
                  cancel: cancelRename)
              : details(context, desktop),
        ),
        if (!editing && !isThisDevice) ...[
          if (desktop) verifyButton(),
          menu(context),
        ],
      ],
    );

    if (isThisDevice) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: scheme.primaryContainer.withAlpha(35),
            border: Border.all(color: scheme.primary.withAlpha(110)),
            borderRadius: BorderRadius.circular(12)),
        child: row,
      );
    }
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
          color: editing ? scheme.surfaceContainerHigh : null,
          borderRadius: BorderRadius.circular(8)),
      child: row,
    );
  }

  Widget details(BuildContext context, bool desktop) {
    final scheme = ColorScheme.of(context);
    final name = displayName?.trim();
    final seen = sessionLastSeenLabel(lastSeenTimestamp, now ?? DateTime.now(),
        isThisDevice: isThisDevice);
    final meta = [
      seen,
      if (desktop && lastSeenIp != null) lastSeenIp!,
      if (desktop) deviceId,
    ].join("  ·  ");

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 3,
      children: [
        Row(spacing: 8, children: [
          Flexible(
            child: name == null || name.isEmpty
                ? Text("Unnamed session",
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontStyle: FontStyle.italic,
                        color: scheme.onSurfaceVariant))
                : tiamat.Text.labelEmphasised(name,
                    overflow: TextOverflow.ellipsis),
          ),
          if (isThisDevice && rename != null)
            SizedBox(
              width: 28,
              height: 28,
              child: Tooltip(
                message: "Rename",
                child: tiamat.IconButton(
                    icon: Icons.edit_outlined,
                    size: 16,
                    onPressed: startRename),
              ),
            ),
          if (inactive)
            TinyPill("Inactive",
                background: scheme.error, foreground: scheme.onError),
        ]),
        Row(spacing: 10, children: [
          if (statusChip(context) case final chip?) chip,
          Flexible(
            child: tiamat.Text.labelLow(meta, overflow: TextOverflow.ellipsis),
          ),
        ]),
      ],
    );
  }

  /// "Verified" or "Not verified", written out; nothing while the keys load.
  Widget? statusChip(BuildContext context) {
    if (!verified && keysState == SessionKeysState.loading) return null;
    final color = verified ? Colors.green : Colors.orange.shade400;
    return Row(mainAxisSize: MainAxisSize.min, spacing: 3, children: [
      Icon(verified ? Icons.verified_rounded : Icons.gpp_maybe_outlined,
          size: 14, color: color),
      Text(verified ? "Verified" : "Not verified",
          style: Theme.of(context)
              .textTheme
              .labelMedium
              ?.copyWith(color: color, fontWeight: FontWeight.w600)),
    ]);
  }

  Widget menu(BuildContext context) {
    final items = [
      if (rename != null)
        tiamat.ContextMenuItem(
            text: "Rename",
            icon: Icons.edit_outlined,
            onPressed: () => startRename?.call()),
      if (canVerify)
        tiamat.ContextMenuItem(
            text: promptMatrixVerifySession,
            icon: Icons.verified_outlined,
            onPressed: () => beginVerification?.call()),
      tiamat.ContextMenuItem(
          text: "Copy session ID",
          icon: Icons.copy_rounded,
          onPressed: () => Clipboard.setData(ClipboardData(text: deviceId))),
      if (removeSession != null)
        tiamat.ContextMenuItem(
            text: "Sign out",
            icon: Icons.logout_rounded,
            color: ColorScheme.of(context).error,
            onPressed: () => removeSession?.call()),
    ];
    return AdaptiveContextMenu(
      modal: true,
      items: items,
      child: Tooltip(
        message: "Session options",
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(Icons.more_horiz_rounded,
              color: ColorScheme.of(context).onSurfaceVariant),
        ),
      ),
    );
  }

  Row verifyButton() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (canVerify)
          tiamat.Button.secondary(
            text: promptMatrixVerifySession,
            onTap: () => beginVerification?.call(),
          ),
        if (verified == false && keysState == SessionKeysState.missing)
          Tooltip(
            message: labelMatrixSessionCannotVerifyExplanation,
            triggerMode: TooltipTriggerMode.tap,
            showDuration: const Duration(seconds: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                tiamat.Text.labelLow(labelMatrixSessionCannotVerify),
                const Padding(
                  padding: EdgeInsets.fromLTRB(4, 0, 0, 0),
                  child: Icon(Icons.info_outline, size: 16),
                ),
              ],
            ),
          ),
      ],
    );
  }

  IconData getIcon() {
    final name = displayName?.toLowerCase();
    if (name == null || name.isEmpty) return Icons.devices_other_rounded;

    bool has(List<String> words) => words.any(name.contains);

    if (has(["tablet", "ipad"])) return Icons.tablet_android_rounded;
    if (has(["ios", "iphone", "android", "mobile", "phone"])) {
      return Icons.smartphone_rounded;
    }
    if (has(["laptop"])) return Icons.laptop_rounded;
    if (has(["desktop", "linux", "windows", "mac", "flatpak"])) {
      return Icons.desktop_windows_rounded;
    }
    if (has(["web", "firefox", "chrome", "safari", "browser"])) {
      return Icons.web_rounded;
    }
    return Icons.devices_other_rounded;
  }
}

/// The name field shown while renaming: Enter saves, Escape cancels.
class _RenameField extends StatefulWidget {
  const _RenameField({required this.initial, this.rename, this.cancel});
  final String initial;
  final Future<void> Function(String name)? rename;
  final VoidCallback? cancel;

  @override
  State<_RenameField> createState() => _RenameFieldState();
}

class _RenameFieldState extends State<_RenameField> {
  late final controller = TextEditingController(text: widget.initial)
    ..selection =
        TextSelection(baseOffset: 0, extentOffset: widget.initial.length);
  bool saving = false;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> save() async {
    final name = controller.text.trim();
    if (saving) return;
    if (name.isEmpty || name == widget.initial.trim()) {
      widget.cancel?.call();
      return;
    }
    setState(() => saving = true);
    try {
      await widget.rename?.call(name);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            widget.cancel?.call(),
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 6,
        children: [
          Row(spacing: 8, children: [
            Expanded(
              child: TextField(
                controller: controller,
                autofocus: true,
                enabled: !saving,
                maxLength: 100,
                decoration: const InputDecoration(
                    isDense: true, counterText: "", hintText: "Session name"),
                onSubmitted: (_) => save(),
              ),
            ),
            tiamat.Button(text: "Save", isLoading: saving, onTap: save),
            tiamat.Button.secondary(
                text: "Cancel", onTap: saving ? null : widget.cancel),
          ]),
          tiamat.Text.labelLow(
              "Session names are visible to people you chat with."),
        ],
      ),
    );
  }
}
