import 'dart:async';

import 'package:commet/client/matrix/components/url_preview/matrix_room_url_previews.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/utils/common_strings.dart';
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
  bool? pendingUserChoice;
  bool userChoicePending = false;

  @override
  void initState() {
    sub = widget.room.client.onSync.stream
        .where((u) => u.rooms?.join?.containsKey(widget.room.id) == true)
        .listen((_) {
      if (!mounted) return;
      setState(() {
        pendingRoomDefault = null;
        userChoicePending = false;
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
      userChoice: userChoicePending ? pendingUserChoice : settings.userChoice,
      defaultEnabled: settings.encrypted
          ? settings.defaultEnabled
          : (pendingRoomDefault ?? settings.defaultEnabled),
      onRoomDefaultChanged: setRoomDefault,
      onUserChoiceChanged: setUserChoice,
    );
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

  Future<void> setUserChoice(bool? value) async {
    setState(() {
      pendingUserChoice = value;
      userChoicePending = true;
    });
    try {
      await settings.setUserChoice(value);
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
    required this.userChoice,
    required this.defaultEnabled,
    this.onRoomDefaultChanged,
    this.onUserChoiceChanged,
    super.key,
  });

  final bool encrypted;

  /// The admins' default for members (unencrypted rooms only).
  final bool roomDefault;
  final bool canChangeRoomDefault;

  /// The user's own choice; null follows [defaultEnabled].
  final bool? userChoice;

  /// What applies without a choice of the user's own.
  final bool defaultEnabled;

  final void Function(bool value)? onRoomDefaultChanged;
  final void Function(bool? value)? onUserChoiceChanged;

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
      "In encrypted rooms, like this one, URL previews are off by default: "
      "to make a preview, your homeserver fetches the link, so it learns "
      "which links are shared here.",
      name: "labelRoomUrlPreviewsEncrypted",
      desc: "Why link previews are off by default in an encrypted room");

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
    String onOff(bool v) =>
        v ? CommonStrings.labelEnabled : CommonStrings.labelDisabled;

    return tiamat.Panel(
      mode: tiamat.TileType.surfaceContainerLow,
      header: labelUrlPreviews,
      mainAxisSize: MainAxisSize.min,
      child: Material(
        color: Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (encrypted)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                child: Text(labelRoomUrlPreviewsEncrypted,
                    style: theme.textTheme.bodyMedium),
              )
            else
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
            tiamat.RadioButton<bool?>(
              groupValue: userChoice,
              value: null,
              icon: Icons.remove_outlined,
              text: encrypted
                  ? labelRoomUrlPreviewsUseGlobal(onOff(defaultEnabled))
                  : labelRoomUrlPreviewsUseRoomDefault(onOff(defaultEnabled)),
              onChanged: onUserChoiceChanged,
            ),
            tiamat.RadioButton<bool?>(
              groupValue: userChoice,
              value: false,
              icon: Icons.link_off,
              text: CommonStrings.labelDisabled,
              onChanged: onUserChoiceChanged,
            ),
            tiamat.RadioButton<bool?>(
              groupValue: userChoice,
              value: true,
              icon: Icons.link,
              text: CommonStrings.labelEnabled,
              onChanged: onUserChoiceChanged,
            ),
          ],
        ),
      ),
    );
  }
}
