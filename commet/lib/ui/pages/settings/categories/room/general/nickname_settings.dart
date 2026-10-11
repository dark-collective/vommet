import 'package:commet/client/client.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/nicknames/matrix_nicknames.dart';
import 'package:commet/client/matrix/nicknames/nickname_rules.dart';
import 'package:commet/debug/log.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

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

  NicknameStatus status() {
    final (name, source, from) = nicknames.effective(widget.roomId);
    final (done, total) = progress ?? (null, null);
    switch (source) {
      case NicknameSource.room:
        return NicknameStatus(
            icon: Icons.tag,
            name: name!,
            source: "set for this room",
            done: done,
            total: total);
      case NicknameSource.space:
        final spaceName = widget.client.getSpace(from!)?.displayName ?? from;
        return NicknameStatus(
            icon: Icons.workspaces_outline,
            name: name!,
            source: from == widget.roomId
                ? "set for this space"
                : "from the space $spaceName",
            done: done,
            total: total);
      case NicknameSource.global:
        return NicknameStatus(
            icon: Icons.person_outline,
            name: widget.client.self?.displayName ?? "your global name",
            source: "your global name",
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
          error = "Couldn't update ${failed.length} room(s)";
        }
      } else {
        await nicknames.setRoomNickname(widget.roomId, name);
      }
      if (name == null) controller.text = "";
    } catch (e) {
      Log.w("Nicknames: couldn't save: $e");
      error = "Couldn't save your nickname. Try again later";
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
      header: isSpace ? "Your nickname in this space" : "Your nickname here",
      mode: tiamat.TileType.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            tiamat.Text.labelLow(isSpace
                ? "Others see this name in the space and every room in it, unless a room has its own nickname."
                : "Others see this name in this room. It overrides a space nickname."),
            const SizedBox(height: 8),
            status(),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              readOnly: busy,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: "Nickname",
                errorText: error,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                tiamat.Button.secondary(
                  text: "Reset",
                  onTap: busy ? null : () => save(null),
                ),
                const SizedBox(width: 8),
                tiamat.Button(
                  text: "Save",
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
                    ? Text("Updating rooms: $done / $total",
                        style: style?.copyWith(color: scheme.onSurface))
                    : Text.rich(
                        TextSpan(children: [
                          TextSpan(
                              text: "Showing as ",
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
