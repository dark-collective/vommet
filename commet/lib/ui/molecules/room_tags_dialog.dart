// Vommet: "Tags…" in a room's menu. Favourite, Low priority and your own
// tags (`u.*`, Matrix `m.tag`), each ticked or not for this room, plus a
// field for a new tag. Changes save straight away; other apps such as Nheko
// show the same tags. New Home's tag cards and sections list these rooms.

import 'package:commet/client/client.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/config/layout_config.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/ui/organisms/new_home/room_tags.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart' as matrix;

const String _favourite = matrix.TagType.favourite;
const String _lowPriority = matrix.TagType.lowPriority;

/// Whether [room] can have tags (Matrix rooms only).
bool canTagRoom(Room room) => room is MatrixRoom;

/// Opens the Tags dialog (a sheet on phones) for [room].
Future<void> showRoomTags(BuildContext context, Room room) async {
  if (room is! MatrixRoom) return;
  await AdaptiveDialog.show(context,
      title: "Tags for ${room.displayName}",
      builder: (context) => RoomTagsEditor(room: room));
}

class RoomTagsEditor extends StatefulWidget {
  const RoomTagsEditor({required this.room, super.key});

  final MatrixRoom room;

  @override
  State<RoomTagsEditor> createState() => _RoomTagsEditorState();
}

class _RoomTagsEditorState extends State<RoomTagsEditor> {
  late final Set<String> _on = widget.room.matrixRoom.tags.keys.toSet();

  /// Your tags on any room, plus ones made here, in the order shown.
  late final List<String> _tags = userTagsOf([
    for (final room in clientManager?.rooms ?? const <Room>[])
      if (room is MatrixRoom) room.matrixRoom.tags.keys,
  ]);

  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _set(String tag, bool on) async {
    final room = widget.room.matrixRoom;
    // Favourite and Low priority exclude each other.
    final other = switch (tag) {
      _favourite => _lowPriority,
      _lowPriority => _favourite,
      _ => null,
    };
    setState(() {
      on ? _on.add(tag) : _on.remove(tag);
      if (on && other != null) _on.remove(other);
    });
    try {
      if (on) {
        if (other != null && room.tags.containsKey(other)) {
          await room.removeTag(other);
        }
        await room.addTag(tag);
      } else {
        await room.removeTag(tag);
      }
    } catch (e, s) {
      Log.onError(e, s, content: "Couldn't change the room's tags");
      if (mounted) {
        setState(() => on ? _on.remove(tag) : _on.add(tag));
      }
    }
  }

  void _add() {
    final tag = tagFromName(_name.text);
    if (tag == null) return;
    _name.clear();
    if (!_tags.contains(tag)) {
      setState(() {
        _tags.add(tag);
        _tags.sort((a, b) =>
            tagName(a).toLowerCase().compareTo(tagName(b).toLowerCase()));
      });
    }
    if (!_on.contains(tag)) _set(tag, true);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final phone = MediaQuery.of(context).mobile;
    final hint = TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant);

    Widget heading(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
          child: Text(text.toUpperCase(),
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                  color: scheme.onSurfaceVariant)),
        );

    Widget option(String tag, String label, IconData icon) => phone
        ? FilterChip(
            avatar: Icon(icon, size: 18),
            label: Text(label),
            selected: _on.contains(tag),
            showCheckmark: false,
            onSelected: (on) => _set(tag, on),
          )
        : CheckboxListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            controlAffinity: ListTileControlAffinity.leading,
            secondary: Icon(icon, size: 20),
            title: Text(label),
            value: _on.contains(tag),
            onChanged: (on) => _set(tag, on ?? false),
          );

    Widget group(List<Widget> options) => phone
        ? Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Wrap(spacing: 8, runSpacing: 8, children: options),
          )
        : Column(children: options);

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Column(
          key: const ValueKey("RoomTagsEditor"),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            group([
              option(_favourite, "Favourite", Icons.star_rounded),
              option(_lowPriority, "Low priority", Icons.south_rounded),
            ]),
            heading("Your tags"),
            if (_tags.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text("You haven't made any tags yet.", style: hint),
              )
            else
              group([
                for (final tag in _tags)
                  option(tag, tagName(tag), Icons.label_outline_rounded),
              ]),
            const SizedBox(height: 12),
            Row(
              spacing: 8,
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey("RoomTagsNewName"),
                    controller: _name,
                    maxLength: maxTagName,
                    decoration: const InputDecoration(
                        isDense: true,
                        counterText: "",
                        hintText: "New tag name"),
                    onSubmitted: (_) => _add(),
                  ),
                ),
                FilledButton.tonal(
                    onPressed: _add, child: const Text("Add tag")),
              ],
            ),
            const SizedBox(height: 10),
            Text(
                "Tags are saved in Matrix, so apps such as Nheko show them "
                "too. In New Home, add a tag's rooms as a card or section "
                "from Customize Home.",
                style: hint),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
