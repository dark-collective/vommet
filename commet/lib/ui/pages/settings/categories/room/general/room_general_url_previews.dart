import 'dart:async';

import 'package:commet/client/components/url_preview/url_preview_room_policy.dart';
import 'package:commet/client/matrix/components/url_preview/matrix_room_url_previews.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/pages/settings/categories/app/link_preview_settings_panel.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:tiamat/tiamat.dart' as tiamat;

/// Vommet: room settings › General › URL previews, for a Matrix room: the
/// admins' default for members (unencrypted rooms) and the user's own choice.
class MatrixRoomUrlPreviewSettings extends StatefulWidget {
  const MatrixRoomUrlPreviewSettings(this.room, {super.key});

  final matrix.Room room;

  @override
  State<MatrixRoomUrlPreviewSettings> createState() =>
      _MatrixRoomUrlPreviewSettingsState();
}

class _MatrixRoomUrlPreviewSettingsState
    extends State<MatrixRoomUrlPreviewSettings> {
  late final MatrixRoomUrlPreviews settings =
      MatrixRoomUrlPreviews(widget.room);
  StreamSubscription? sub;

  // Shown straight away; the next sync brings the stored value.
  bool? pendingRoomDefault;
  UrlPreviewMode? pendingUserMode;
  bool userChoicePending = false;
  bool bundledConsentPending = false;
  bool? pendingBundledConsent;

  /// "Everyone in this chat" (true), "Never in this chat" (false) or unset.
  bool? get bundledConsent =>
      bundledConsentPending ? pendingBundledConsent : settings.bundledConsent;

  @override
  void initState() {
    sub = widget.room.client.onSync.stream
        .where((u) => u.rooms?.join?.containsKey(widget.room.id) == true)
        .listen((_) {
      if (!mounted) return;
      setState(() {
        pendingRoomDefault = null;
        userChoicePending = false;
        bundledConsentPending = false;
        pendingBundledConsent = null;
      });
    });
    super.initState();
  }

  @override
  void dispose() {
    sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RoomUrlPreviewSettingsView(
      encrypted: settings.encrypted,
      roomDefault: pendingRoomDefault ?? settings.roomDefault ?? true,
      canChangeRoomDefault: settings.canChangeRoomDefault,
      userMode: userChoicePending ? pendingUserMode : settings.userMode,
      defaultMode: resolveUrlPreviewMode(
          encrypted: settings.encrypted,
          roomDefault: pendingRoomDefault ?? settings.roomDefault,
          globalMode: globalUrlPreviewModeSetting),
      globalIsAutomatic: globalUrlPreviewModeSetting == null,
      onRoomDefaultChanged: setRoomDefault,
      onUserModeChanged: setUserMode,
      // Shown while chats ask, and for a chat set to "Never in this chat"
      // (hidden even when nothing asks).
      bundledConsent: preferences.bundledUrlPreviewsAskInNewChats.value ||
              bundledConsent == false
          ? bundledConsent == true
          : null,
      bundledNever: bundledConsent == false,
      onBundledConsentChanged: setBundledConsent,
    );
  }

  /// On = "Everyone in this chat"; off = ask again (Vommet issue 676).
  Future<void> setBundledConsent(bool value) async {
    final stored = value ? true : null;
    setState(() {
      bundledConsentPending = true;
      pendingBundledConsent = stored;
    });
    try {
      await settings.setBundledConsent(stored);
    } catch (e) {
      Log.w("Couldn't save the bundled preview choice for this room: $e");
      if (mounted) setState(() => bundledConsentPending = false);
    }
  }

  Future<void> setRoomDefault(bool value) async {
    setState(() => pendingRoomDefault = value);
    try {
      await settings.setRoomDefault(value);
    } catch (e) {
      Log.w("Couldn't change the room's URL preview default: $e");
      if (mounted) setState(() => pendingRoomDefault = null);
    }
  }

  Future<void> setUserMode(UrlPreviewMode? value) async {
    setState(() {
      pendingUserMode = value;
      userChoicePending = true;
    });
    try {
      await settings.setUserMode(value);
    } catch (e) {
      Log.w("Couldn't save the URL preview choice for this room: $e");
      if (mounted) setState(() => userChoicePending = false);
    }
  }
}

/// The URL previews panel itself, fed plain values.
class RoomUrlPreviewSettingsView extends StatelessWidget {
  const RoomUrlPreviewSettingsView({
    required this.encrypted,
    required this.roomDefault,
    required this.canChangeRoomDefault,
    required this.userMode,
    required this.defaultMode,
    this.globalIsAutomatic = true,
    this.onRoomDefaultChanged,
    this.onUserModeChanged,
    this.bundledConsent,
    this.bundledNever = false,
    this.onBundledConsentChanged,
    super.key,
  });

  final bool encrypted;

  /// The admins' default for members (unencrypted rooms only).
  final bool roomDefault;
  final bool canChangeRoomDefault;

  /// The user's own mode; null follows [defaultMode].
  final UrlPreviewMode? userMode;

  /// What applies without a choice of the user's own.
  final UrlPreviewMode defaultMode;

  /// The global default is Automatic, so an unencrypted room follows its
  /// admins' default.
  final bool globalIsAutomatic;

  final void Function(bool value)? onRoomDefaultChanged;
  final void Function(UrlPreviewMode? value)? onUserModeChanged;

  /// Vommet issue 676: whether previews other people's apps bundle show here
  /// without asking; null hides the switch (no chat asks).
  final bool? bundledConsent;

  /// The user chose "Never in this chat" on a preview card.
  final bool bundledNever;
  final void Function(bool value)? onBundledConsentChanged;

  static String get labelRoomBundledPreviewsHeader =>
      Intl.message("Sender-made previews in this chat",
          name: "labelRoomBundledPreviewsHeader",
          desc: "Sub-header above the switch for link previews that the "
              "sender's app attached");

  static String get labelRoomBundledPreviewsTitle =>
      Intl.message("Show without asking",
          name: "labelRoomBundledPreviewsTitle",
          desc: "Switch: show sender-made link previews in this chat without "
              "asking first");

  static String get labelRoomBundledPreviewsDescription => Intl.message(
      "Previews other people's apps attach to their links. Turn off to be asked again.",
      name: "labelRoomBundledPreviewsDescription",
      desc: "Explains the switch for sender-made link previews in a room");

  static String get labelRoomBundledPreviewsNeverDescription => Intl.message(
      "Hidden here: you chose “Never in this chat”. Turn on to show them.",
      name: "labelRoomBundledPreviewsNeverDescription",
      desc: "Explains the switch for sender-made link previews in a room "
          "where the user chose to never show them");

  static String get labelUrlPreviews => Intl.message("URL previews",
      name: "labelRoomUrlPreviews",
      desc: "Header of the room settings panel for link previews");

  static String get labelRoomUrlPreviewsDefaultTitle =>
      Intl.message("Show previews by default",
          name: "labelRoomUrlPreviewsDefaultTitle",
          desc: "Room admins' switch: link previews on for members by default");

  static String get labelRoomUrlPreviewsDefaultDescription => Intl.message(
      "For everyone in this room who hasn't chosen for themselves.",
      name: "labelRoomUrlPreviewsDefaultDescription",
      desc: "Explains the room admins' link preview default");

  static String get labelRoomUrlPreviewsDefaultReadOnly => Intl.message(
      "Only people who can change room settings can change this.",
      name: "labelRoomUrlPreviewsDefaultReadOnly",
      desc: "Under the link preview default when the user may not change it");

  static String get labelRoomUrlPreviewsEncrypted => Intl.message(
      "This room is encrypted. Bundled previews are made by the sender’s app and travel inside the encrypted message, so your homeserver never learns which links are shared here. Homeserver previews send each link to your homeserver to fetch.",
      name: "labelRoomUrlPreviewsEncryptedBundled",
      desc: "Explains bundled and homeserver link previews in an encrypted "
          "room");

  static String get labelRoomUrlPreviewsUnencrypted => Intl.message(
      "Bundled previews are made by the sender’s app and travel inside the message. Homeserver previews send each link to your homeserver to fetch.",
      name: "labelRoomUrlPreviewsUnencryptedBundled",
      desc: "Explains bundled and homeserver link previews in an unencrypted "
          "room");

  static String get labelRoomUrlPreviewsYourChoice =>
      Intl.message("For you in this room",
          name: "labelRoomUrlPreviewsYourChoice",
          desc: "Sub-header above the user's own link preview choice");

  static String labelRoomUrlPreviewsUseRoomDefault(String value) =>
      Intl.message("Use the room's default ($value)",
          args: [value],
          name: "labelRoomUrlPreviewsUseRoomDefault",
          desc: "Follow the room's link preview default, showing its value");

  static String labelRoomUrlPreviewsUseGlobal(String value) => Intl.message(
      "Use global preference ($value)",
      args: [value],
      name: "labelRoomUrlPreviewsUseGlobal",
      desc:
          "Follow the app-wide link preview setting for encrypted chats, showing its value");

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return tiamat.Panel(
      mode: tiamat.TileType.surfaceContainerLow,
      header: labelUrlPreviews,
      mainAxisSize: MainAxisSize.min,
      child: Material(
        color: Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
              child: Text(
                  encrypted
                      ? labelRoomUrlPreviewsEncrypted
                      : labelRoomUrlPreviewsUnencrypted,
                  style: theme.textTheme.bodyMedium),
            ),
            if (!encrypted)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          tiamat.Text.labelEmphasised(
                              labelRoomUrlPreviewsDefaultTitle),
                          tiamat.Text.labelLow(canChangeRoomDefault
                              ? labelRoomUrlPreviewsDefaultDescription
                              : labelRoomUrlPreviewsDefaultReadOnly),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 8, 0, 8),
                      child: Opacity(
                        opacity: canChangeRoomDefault ? 1 : 0.5,
                        child: tiamat.Switch(
                          state: roomDefault,
                          onChanged: canChangeRoomDefault
                              ? onRoomDefaultChanged
                              : null,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
              child: tiamat.Text.labelLow(labelRoomUrlPreviewsYourChoice),
            ),
            LinkPreviewModeOption<UrlPreviewMode?>(
              groupValue: userMode,
              value: null,
              icon: Icons.remove_outlined,
              text: encrypted || !globalIsAutomatic
                  ? labelRoomUrlPreviewsUseGlobal(
                      LinkPreviewModeLabels.of(defaultMode))
                  : labelRoomUrlPreviewsUseRoomDefault(
                      LinkPreviewModeLabels.of(defaultMode)),
              onChanged: onUserModeChanged,
            ),
            for (final mode in const [
              UrlPreviewMode.off,
              UrlPreviewMode.bundledOnly,
              UrlPreviewMode.all,
            ])
              LinkPreviewModeOption<UrlPreviewMode?>(
                groupValue: userMode,
                value: mode,
                icon: LinkPreviewModeLabels.iconOf(mode),
                text: LinkPreviewModeLabels.of(mode),
                description: LinkPreviewModeLabels.descriptionOf(mode),
                onChanged: onUserModeChanged,
              ),
            if (bundledConsent != null) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
                child: tiamat.Text.labelLow(labelRoomBundledPreviewsHeader),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          tiamat.Text.labelEmphasised(
                              labelRoomBundledPreviewsTitle),
                          tiamat.Text.labelLow(bundledNever
                              ? labelRoomBundledPreviewsNeverDescription
                              : labelRoomBundledPreviewsDescription),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 8, 0, 8),
                      child: tiamat.Switch(
                        state: bundledConsent!,
                        onChanged: onBundledConsentChanged,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
