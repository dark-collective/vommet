import 'dart:typed_data';

import 'package:commet/client/client.dart';
import 'package:commet/client/components/chat_wallpaper/chat_wallpaper_component.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/ui/organisms/chat_wallpaper/chat_wallpaper_view.dart';
import 'package:commet/utils/common_strings.dart';
import 'package:commet/utils/error_utils.dart';
import 'package:commet/utils/picker_utils.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Vommet issue 746: pick, adjust, preview and apply a 1:1 chat's shared
/// wallpaper; switch back to a recent one or remove it. Nothing changes
/// until Apply (or Remove wallpaper).
class ChatWallpaperEditor extends StatefulWidget {
  const ChatWallpaperEditor({required this.component, super.key});
  final ChatWallpaperComponent component;

  static String get chatWallpaperTitle => Intl.message("Chat wallpaper",
      name: "chatWallpaperTitle",
      desc:
          "Title of the dialog where a 1:1 chat's shared wallpaper is picked and adjusted, and the room menu entry that opens it");

  static String get chatWallpaperUploadImage => Intl.message("Upload image",
      name: "chatWallpaperUploadImage",
      desc: "Button in the chat wallpaper dialog that picks a picture");

  static String get chatWallpaperDarkerLighter => Intl.message(
      "Darker / lighter",
      name: "chatWallpaperDarkerLighter",
      desc:
          "Label of the slider that darkens (left) or lightens (right) the chat wallpaper");

  static String get chatWallpaperBlur => Intl.message("Blur",
      name: "chatWallpaperBlur",
      desc: "Label of the slider that blurs the chat wallpaper");

  static String get chatWallpaperRecent => Intl.message("Recent",
      name: "chatWallpaperRecent",
      desc: "Heading over the grid of recently applied chat wallpapers");

  static String get chatWallpaperSelect => Intl.message("Select",
      name: "chatWallpaperSelect",
      desc:
          "Button that lets you pick recent chat wallpapers to remove them from the list");

  static String get chatWallpaperSelectDone => Intl.message("Done",
      name: "chatWallpaperSelectDone",
      desc: "Button that ends selecting recent chat wallpapers");

  static String chatWallpaperRemoveFromRecent(int count) => Intl.message(
      "Remove from Recent ($count)",
      args: [count],
      name: "chatWallpaperRemoveFromRecent",
      desc:
          "Button that removes the selected wallpapers from the Recent list (only yours; the chat's wallpaper is not changed)");

  static String get chatWallpaperRemove => Intl.message("Remove wallpaper",
      name: "chatWallpaperRemove",
      desc:
          "Button that removes the chat's wallpaper for both people in the chat");

  static String get chatWallpaperNone =>
      Intl.message("No wallpaper yet. Upload a picture to pick one.",
          name: "chatWallpaperNone",
          desc: "Shown in the wallpaper preview before a picture is picked");

  static String get chatWallpaperAppliesToBoth =>
      Intl.message("Applies for both of you. Only shows in this chat.",
          name: "chatWallpaperAppliesToBoth",
          desc: "Note in the chat wallpaper dialog, above the Apply button");

  static String get chatWallpaperCantChange => Intl.message(
      "You don't have permission to change this chat's wallpaper.",
      name: "chatWallpaperCantChange",
      desc:
          "Shown in the chat wallpaper dialog when the room's permissions don't let you change it");

  static String get chatWallpaperSampleTheirs => Intl.message(
      "Are we still on for Saturday?",
      name: "chatWallpaperSampleTheirs",
      desc:
          "Sample message from the other person, shown over the wallpaper preview");

  static String get chatWallpaperSampleMine =>
      Intl.message("Yes! I'll bring the map.",
          name: "chatWallpaperSampleMine",
          desc: "Sample message from you, shown over the wallpaper preview");

  static Future<void> show(
      BuildContext context, ChatWallpaperComponent component) {
    return AdaptiveDialog.show(context,
        title: chatWallpaperTitle,
        builder: (context) => ChatWallpaperEditor(component: component));
  }

  /// The room's wallpaper component when the editor can open here.
  static ChatWallpaperComponent? availableIn(Room room) {
    final component = room.getComponent<ChatWallpaperComponent>();
    return component?.isAvailable == true ? component : null;
  }

  @override
  State<ChatWallpaperEditor> createState() => _ChatWallpaperEditorState();
}

class _ChatWallpaperEditorState extends State<ChatWallpaperEditor> {
  ChatWallpaper? current;
  List<ChatWallpaper> recent = [];

  /// The wallpaper being adjusted (current or one from Recent), when no new
  /// picture was picked.
  ChatWallpaper? base;
  Uint8List? picked;
  double dim = 0;
  double blur = 0;

  bool loading = true;
  bool busy = false;
  bool selecting = false;
  final Set<String> selected = {};

  ChatWallpaperComponent get component => widget.component;

  Uint8List? get bytes => picked ?? base?.bytes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final current = await component.current();
    final recent = await component.recent();
    if (!mounted) return;
    setState(() {
      this.current = current;
      this.recent = recent;
      loading = false;
      if (current != null) _use(current);
    });
  }

  void _use(ChatWallpaper wallpaper) {
    base = wallpaper;
    picked = null;
    dim = wallpaper.dim;
    blur = wallpaper.blur;
  }

  Future<void> _pick() async {
    final result = await PickerUtils.pickImage();
    if (result == null) return;
    final data = await result.readAsBytes();
    if (!mounted) return;
    final dark = Theme.of(context).brightness == Brightness.dark;
    setState(() {
      picked = data;
      base = null;
      // Messages aren't in bubbles, so start where text stays readable.
      dim = dark ? -0.4 : 0.4;
      blur = 0;
    });
  }

  Future<void> _apply() async {
    setState(() => busy = true);
    await ErrorUtils.tryRun(context, () async {
      await component.apply(image: picked, from: base, dim: dim, blur: blur);
      if (mounted) Navigator.of(context).pop();
    });
    if (mounted) setState(() => busy = false);
  }

  Future<void> _remove() async {
    setState(() => busy = true);
    await ErrorUtils.tryRun(context, () async {
      await component.remove();
      if (mounted) Navigator.of(context).pop();
    });
    if (mounted) setState(() => busy = false);
  }

  Future<void> _removeSelected() async {
    final ids = Set.of(selected);
    setState(() => busy = true);
    await ErrorUtils.tryRun(context, () async {
      await component.removeRecent(ids);
      if (!mounted) return;
      setState(() {
        recent.removeWhere((w) => ids.contains(w.id));
        selected.clear();
        selecting = false;
      });
    });
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const SizedBox(
          width: 420,
          height: 200,
          child: Center(child: CircularProgressIndicator()));
    }
    final canChange = component.canChange;
    return SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          if (!canChange)
            tiamat.Text.labelLow(ChatWallpaperEditor.chatWallpaperCantChange),
          if (canChange)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                  onPressed: busy ? null : _pick,
                  icon: const Icon(Icons.upload),
                  label: Text(ChatWallpaperEditor.chatWallpaperUploadImage)),
            ),
          _preview(context),
          if (bytes != null && canChange) ...[
            _slider(ChatWallpaperEditor.chatWallpaperDarkerLighter, dim, -1,
                (v) => setState(() => dim = v)),
            _slider(ChatWallpaperEditor.chatWallpaperBlur, blur, 0,
                (v) => setState(() => blur = v)),
          ],
          if (recent.isNotEmpty) _recent(context),
          if (canChange) ...[
            tiamat.Text.labelLow(
                ChatWallpaperEditor.chatWallpaperAppliesToBoth),
            Row(
              children: [
                if (current != null)
                  TextButton(
                      onPressed: busy ? null : _remove,
                      style: TextButton.styleFrom(
                          foregroundColor: Theme.of(context).colorScheme.error),
                      child: Text(ChatWallpaperEditor.chatWallpaperRemove)),
                const Spacer(),
                TextButton(
                    onPressed: busy ? null : () => Navigator.of(context).pop(),
                    child: Text(CommonStrings.promptCancel)),
                const SizedBox(width: 8),
                FilledButton(
                    onPressed: busy || bytes == null ? null : _apply,
                    child: Text(CommonStrings.promptApply)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _preview(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bytes = this.bytes;
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 200,
        color: scheme.surfaceContainerLow,
        child: Stack(fit: StackFit.expand, children: [
          if (bytes != null)
            ChatWallpaperView(
                bytes: bytes, dim: dim, blur: blur, blurScale: 0.5)
          else
            Center(
                child: Padding(
              padding: const EdgeInsets.all(16),
              child:
                  tiamat.Text.labelLow(ChatWallpaperEditor.chatWallpaperNone),
            )),
          if (bytes != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _sample(
                      context, ChatWallpaperEditor.chatWallpaperSampleTheirs,
                      mine: false),
                  const SizedBox(height: 8),
                  _sample(context, ChatWallpaperEditor.chatWallpaperSampleMine,
                      mine: true),
                ],
              ),
            ),
        ]),
      ),
    );
  }

  /// A message as the chat draws it: plain text on the wallpaper.
  Widget _sample(BuildContext context, String text, {required bool mine}) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
              radius: 10,
              backgroundColor: mine ? scheme.primary : scheme.tertiary),
          const SizedBox(width: 8),
          Flexible(
              child: Text(text,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: scheme.onSurface))),
        ],
      ),
    );
  }

  Widget _slider(
      String label, double value, double min, void Function(double) onChanged) {
    return Row(children: [
      SizedBox(width: 130, child: tiamat.Text.label(label)),
      Expanded(
        child: Slider(
            value: value.clamp(min, 1.0),
            min: min,
            max: 1,
            onChanged: busy ? null : onChanged),
      ),
    ]);
  }

  Widget _recent(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: [
        Row(children: [
          Expanded(
              child: tiamat.Text.labelEmphasised(
                  ChatWallpaperEditor.chatWallpaperRecent)),
          TextButton(
              onPressed: busy
                  ? null
                  : () => setState(() {
                        selecting = !selecting;
                        selected.clear();
                      }),
              child: Text(selecting
                  ? ChatWallpaperEditor.chatWallpaperSelectDone
                  : ChatWallpaperEditor.chatWallpaperSelect)),
        ]),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final w in recent)
            _thumbnail(context, w,
                active: selecting
                    ? selected.contains(w.id)
                    : picked == null && base?.id == w.id),
        ]),
        if (selecting)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
                onPressed: busy || selected.isEmpty ? null : _removeSelected,
                style: TextButton.styleFrom(foregroundColor: scheme.error),
                child: Text(ChatWallpaperEditor.chatWallpaperRemoveFromRecent(
                    selected.length))),
          ),
      ],
    );
  }

  Widget _thumbnail(BuildContext context, ChatWallpaper w,
      {required bool active}) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: busy
          ? null
          : () => setState(() {
                if (selecting) {
                  if (!selected.remove(w.id)) selected.add(w.id);
                } else if (component.canChange) {
                  _use(w);
                }
              }),
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: active ? scheme.primary : Colors.transparent, width: 2),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Stack(fit: StackFit.expand, children: [
            ChatWallpaperView(
                bytes: w.bytes,
                dim: w.dim,
                blur: w.blur,
                blurScale: 0.2,
                decodeWidth: 160),
            if (selecting)
              Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                      active
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      size: 18,
                      color: active ? scheme.primary : Colors.white),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}
