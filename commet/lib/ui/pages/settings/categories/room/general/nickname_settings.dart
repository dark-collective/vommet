import 'package:commet/client/client.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/nicknames/matrix_nicknames.dart';
import 'package:commet/client/matrix/nicknames/nickname_rules.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/main.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;
import 'package:intl/intl.dart';

/// Vommet: "Your nickname in this room / space" (Vommet issue 69). Pass
/// [space] for a space's settings; otherwise it edits the room's own
/// override.
class NicknameSettings extends StatefulWidget {
  const NicknameSettings(
      {super.key, required this.client, required this.roomId, this.space});

  final MatrixClient client;
  final String roomId;
  final Space? space;

  @override
  State<NicknameSettings> createState() => _NicknameSettingsState();
}

class _NicknameSettingsState extends State<NicknameSettings> {
  final controller = TextEditingController();
  bool busy = false;
  (int, int)? progress;
  String? error;

  MatrixNicknames get nicknames => MatrixNicknames.of(widget.client);
  bool get isSpace => widget.space != null;

  @override
  void initState() {
    final rules = nicknames.rules;
    controller.text =
        (isSpace ? rules.spaces[widget.roomId] : rules.rooms[widget.roomId]) ??
            "";
    super.initState();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  /// With several accounts signed in, each has its own copy of a shared room
  /// or space, so the title says which one this panel edits.
  String accountLabel() {
    if ((clientManager?.clients.length ?? 0) < 2) return "";
    final me = widget.client.getMatrixClient().userID;
    return me == null ? "" : nicknameSettingsAsAccount(me);
  }

  NicknameStatus status() {
    final (name, source, from) = nicknames.effective(widget.roomId);
    final (done, total) = progress ?? (null, null);
    switch (source) {
      case NicknameSource.room:
        return NicknameStatus(
            icon: Icons.tag,
            name: name!,
            source: nicknameSettingsSourceRoom,
            done: done,
            total: total);
      case NicknameSource.space:
        final spaceName = widget.client.getSpace(from!)?.displayName ?? from;
        return NicknameStatus(
            icon: Icons.workspaces_outline,
            name: name!,
            source: from == widget.roomId
                ? nicknameSettingsSourceThisSpace
                : nicknameSettingsSourceParentSpace(spaceName),
            done: done,
            total: total);
      case NicknameSource.global:
        return NicknameStatus(
            icon: Icons.person_outline,
            name: widget.client.self?.displayName ?? nicknameSettingsGlobalName,
            source: nicknameSettingsGlobalName,
            done: done,
            total: total);
    }
  }

  Future<void> save(String? name) async {
    setState(() {
      busy = true;
      error = null;
      progress = null;
    });
    try {
      if (isSpace) {
        final failed = await nicknames.setSpaceNickname(widget.space!, name,
            onProgress: (done, total) {
          if (mounted) {
            setState(() => progress = (done, total));
          }
        });
        if (failed.isNotEmpty) {
          error = nicknameSettingsRoomsFailed(failed.length);
        }
      } else {
        await nicknames.setRoomNickname(widget.roomId, name);
      }
      if (name == null) controller.text = "";
    } catch (e) {
      Log.w("Nicknames: couldn't save: $e");
      error = nicknameSettingsSaveFailed;
    }
    if (mounted) {
      setState(() {
        busy = false;
        progress = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return tiamat.Panel(
      header:
          (isSpace ? nicknameSettingsHeaderSpace : nicknameSettingsHeaderRoom) +
              accountLabel(),
      mode: tiamat.TileType.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            tiamat.Text.labelLow(isSpace
                ? nicknameSettingsExplainSpace
                : nicknameSettingsExplainRoom),
            const SizedBox(height: 8),
            status(),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              readOnly: busy,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: nicknameSettingsFieldLabel,
                errorText: error,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                tiamat.Button.secondary(
                  text: nicknameSettingsReset,
                  onTap: busy ? null : () => save(null),
                ),
                const SizedBox(width: 8),
                tiamat.Button(
                  text: nicknameSettingsSave,
                  isLoading: busy,
                  onTap: busy ? null : () => save(controller.text),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Vommet: the panel's state line, "Showing as <name> · <where it comes
/// from>", set apart from the explanation above it by a tinted background,
/// an accent bar and the name in bold. While rooms are being updated it
/// shows the progress instead.
class NicknameStatus extends StatelessWidget {
  const NicknameStatus(
      {super.key,
      required this.icon,
      required this.name,
      required this.source,
      this.done,
      this.total});

  final IconData icon;
  final String name;
  final String source;
  final int? done;
  final int? total;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme.bodyMedium;
    final updating = done != null && total != null && total! > 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: scheme.primary, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(updating ? Icons.sync : icon,
                  size: 18, color: scheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: updating
                    ? Text(nicknameSettingsUpdating(done!, total!),
                        style: style?.copyWith(color: scheme.onSurface))
                    : Text.rich(
                        TextSpan(children: [
                          TextSpan(
                              text: nicknameSettingsShowingAs,
                              style: TextStyle(color: scheme.onSurface)),
                          TextSpan(
                              text: name,
                              style: TextStyle(
                                  color: scheme.onSurface,
                                  fontWeight: FontWeight.bold)),
                          TextSpan(
                              text: "  ·  $source",
                              style: TextStyle(color: scheme.onSurfaceVariant)),
                        ]),
                        style: style,
                      ),
              ),
            ],
          ),
          if (updating) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: done! / total!,
              borderRadius: BorderRadius.circular(2),
            ),
          ],
        ],
      ),
    );
  }
}

String nicknameSettingsAsAccount(String account) => Intl.message(
    " (as $account)",
    args: [account],
    name: "nicknameSettingsAsAccount",
    desc:
        "Appended to the nickname panel header when several accounts are signed in (keep the leading space); account is a Matrix user ID");

String get nicknameSettingsSourceRoom => Intl.message("used in this room only",
    name: "nicknameSettingsSourceRoom",
    desc: "Where the shown nickname comes from: set for this room only");

String get nicknameSettingsSourceThisSpace =>
    Intl.message("used across this space",
        name: "nicknameSettingsSourceThisSpace",
        desc: "Where the shown nickname comes from: set for this whole space");

String nicknameSettingsSourceParentSpace(String space) => Intl.message(
    "from the space $space",
    args: [space],
    name: "nicknameSettingsSourceParentSpace",
    desc:
        "Where the shown nickname comes from: a parent space; space is its name");

String get nicknameSettingsGlobalName => Intl.message("your global name",
    name: "nicknameSettingsGlobalName",
    desc:
        "Shown in place of the display name when it is unknown; also the source label for the global display name");

String nicknameSettingsRoomsFailed(int count) => Intl.plural(count,
    one: "Couldn't update 1 room",
    other: "Couldn't update $count room(s)",
    args: [count],
    name: "nicknameSettingsRoomsFailed",
    desc: "Error when the space nickname could not be set in some rooms");

String get nicknameSettingsSaveFailed =>
    Intl.message("Couldn't save your nickname. Try again later",
        name: "nicknameSettingsSaveFailed",
        desc: "Error when saving the nickname failed");

String get nicknameSettingsHeaderSpace =>
    Intl.message("Your nickname in this space",
        name: "nicknameSettingsHeaderSpace",
        desc: "Header of the nickname panel in space settings");

String get nicknameSettingsHeaderRoom => Intl.message("Your nickname here",
    name: "nicknameSettingsHeaderRoom",
    desc: "Header of the nickname panel in room settings");

String get nicknameSettingsExplainSpace => Intl.message(
    "Others see this name in the space and every room in it, unless a room has its own nickname.",
    name: "nicknameSettingsExplainSpace",
    desc: "Explanation in the space nickname panel");

String get nicknameSettingsExplainRoom => Intl.message(
    "Others see this name in this room. It overrides a space nickname.",
    name: "nicknameSettingsExplainRoom",
    desc: "Explanation in the room nickname panel");

String get nicknameSettingsFieldLabel => Intl.message("Nickname",
    name: "nicknameSettingsFieldLabel",
    desc: "Label of the nickname text field");

String get nicknameSettingsReset => Intl.message("Reset",
    name: "nicknameSettingsReset", desc: "Button that removes the nickname");

String get nicknameSettingsSave => Intl.message("Save",
    name: "nicknameSettingsSave", desc: "Button that saves the nickname");

String nicknameSettingsUpdating(int done, int total) =>
    Intl.message("Updating rooms: $done / $total",
        args: [done, total],
        name: "nicknameSettingsUpdating",
        desc: "Progress while setting a space nickname in each room");

String get nicknameSettingsShowingAs => Intl.message("Showing as ",
    name: "nicknameSettingsShowingAs",
    desc:
        "Start of the line showing the current nickname; the name follows in bold (keep the trailing space)");
