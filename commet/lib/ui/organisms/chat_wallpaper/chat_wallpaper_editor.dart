import 'dart:typed_data';

import 'package:commet/client/client.dart';
import 'package:commet/client/components/chat_wallpaper/chat_wallpaper_component.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/ui/organisms/chat_wallpaper/chat_wallpaper_view.dart';
import 'package:commet/ui/pages/settings/categories/app/theme_settings/theme_color_picker.dart';
import 'package:commet/utils/common_strings.dart';
import 'package:commet/utils/error_utils.dart';
import 'package:commet/utils/picker_utils.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Vommet issue 746: pick, adjust, preview and apply a chat's wallpaper (a
/// picture or colors), for everyone or only for you; switch back to a recent
/// one or remove it. Nothing changes until Apply (or Remove wallpaper).
class ChatWallpaperEditor extends StatefulWidget {
  const ChatWallpaperEditor({required this.component, super.key});
  final ChatWallpaperComponent component;

  static String get chatWallpaperTitle => Intl.message("Chat wallpaper",
      name: "chatWallpaperTitle",
      desc:
          "Title of the dialog where a chat's wallpaper is picked and adjusted, and the room menu entry that opens it");

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
          "Button that removes the chat's wallpaper for everyone in the chat");

  static String get chatWallpaperNone =>
      Intl.message("No wallpaper yet. Upload a picture or pick colors.",
          name: "chatWallpaperNone",
          desc: "Shown in the wallpaper preview before a picture is picked");

  static String get chatWallpaperAppliesToBoth =>
      Intl.message("Applies for both of you. Only shows in this chat.",
          name: "chatWallpaperAppliesToBoth",
          desc: "Note in the chat wallpaper dialog, above the Apply button");

  static String get chatWallpaperAppliesToEveryone => Intl.message(
      "Applies for everyone here. Only shows in this chat.",
      name: "chatWallpaperAppliesToEveryone",
      desc: "Note in a group's chat wallpaper dialog, above the Apply button");

  static String get chatWallpaperCantChange => Intl.message(
      "You don't have permission to change the wallpaper everyone sees here. You can still pick one only for you.",
      name: "chatWallpaperCantChange",
      desc:
          "Shown in the chat wallpaper dialog when the room's permissions don't let you change the shared wallpaper");

  static String get chatWallpaperTabPicture => Intl.message("Picture",
      name: "chatWallpaperTabPicture",
      desc: "Tab in the chat wallpaper dialog for a picture wallpaper");

  static String get chatWallpaperTabColors => Intl.message("Colors",
      name: "chatWallpaperTabColors",
      desc:
          "Tab in the chat wallpaper dialog for a wallpaper made of one to four colors");

  static String get chatWallpaperAddColor => Intl.message("Add color",
      name: "chatWallpaperAddColor",
      desc: "Tooltip of the + button that adds a color to a color wallpaper");

  static String get chatWallpaperRemoveColor => Intl.message("Remove color",
      name: "chatWallpaperRemoveColor",
      desc: "Button that removes one color from a color wallpaper");

  static String get chatWallpaperPickColor => Intl.message("Wallpaper color",
      name: "chatWallpaperPickColor",
      desc: "Title of the dialog that changes one color of a color wallpaper");

  static String get chatWallpaperAnimate => Intl.message(
      "Move with new messages",
      name: "chatWallpaperAnimate",
      desc:
          "Switch in the chat wallpaper dialog: the colors shift a little each time a message comes or goes (3 or 4 colors)");

  static String get chatWallpaperForBoth => Intl.message("For both of us",
      name: "chatWallpaperForBoth",
      desc:
          "Choice in a 1:1 chat's wallpaper dialog: the wallpaper is set for you and the other person");

  static String get chatWallpaperForEveryone => Intl.message("For everyone",
      name: "chatWallpaperForEveryone",
      desc:
          "Choice in a group's wallpaper dialog: the wallpaper is set for everyone in the group");

  static String get chatWallpaperOnlyForMe => Intl.message("Only for me",
      name: "chatWallpaperOnlyForMe",
      desc:
          "Choice in the chat wallpaper dialog: the wallpaper is only shown to you");

  static String get chatWallpaperOnlyForMeNote => Intl.message(
      "Only you see it, on all your devices. No one else is told.",
      name: "chatWallpaperOnlyForMeNote",
      desc:
          "Note in the chat wallpaper dialog, above the Apply button, while Only for me is picked");

  static String get chatWallpaperOnlyForMeServerNote => Intl.message(
      "Unlike your messages here, your homeserver could open this picture.",
      name: "chatWallpaperOnlyForMeServerNote",
      desc:
          "Extra note in an encrypted chat's wallpaper dialog when a picture is set Only for me (its key is kept in settings the homeserver can read)");

  static String get chatWallpaperRemoveOwn => Intl.message(
      "Remove my wallpaper",
      name: "chatWallpaperRemoveOwn",
      desc:
          "Button that removes the wallpaper only you see, so the chat's shared one shows again");

  /// Ready-made color wallpapers.
  static const List<List<Color>> presets = [
    [
      Color(0xffdbddbb),
      Color(0xff6ba587),
      Color(0xffd5d88d),
      Color(0xff88b884)
    ],
    [
      Color(0xfffec496),
      Color(0xffdd6cb9),
      Color(0xff962fbf),
      Color(0xff4f5bd5)
    ],
    [
      Color(0xff85d685),
      Color(0xff67a3f2),
      Color(0xff8fd8e0),
      Color(0xffc2e8a4)
    ],
    [
      Color(0xff7fa381),
      Color(0xfffff5c5),
      Color(0xff336f55),
      Color(0xfffbe37d)
    ],
    [Color(0xff3a4450)],
    [Color(0xffe8dcc8)],
    [Color(0xff2b3a55), Color(0xff6c4f8a)],
    [Color(0xfff4a261), Color(0xffe76f51)],
  ];

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

enum _Tab { picture, colors }

class _ChatWallpaperEditorState extends State<ChatWallpaperEditor> {
  ChatWallpaper? shared;
  ChatWallpaper? own;
  List<ChatWallpaper> recent = [];

  _Tab tab = _Tab.picture;

  /// The wallpaper being adjusted (current or one from Recent), when no new
  /// picture was picked.
  ChatWallpaper? base;
  Uint8List? picked;
  double dim = 0;
  double blur = 0;

  /// The colors of a color wallpaper, empty until some are picked.
  List<Color> colors = [];
  bool animate = true;

  /// Apply only for us instead of for everyone.
  bool onlyForMe = false;

  bool loading = true;
  bool busy = false;
  bool selecting = false;
  final Set<String> selected = {};

  ChatWallpaperComponent get component => widget.component;

  Uint8List? get bytes => picked ?? (base?.fill == null ? base?.bytes : null);

  WallpaperFill? get fill => colors.isEmpty
      ? null
      : WallpaperFill(List.of(colors), animate: animate && colors.length >= 3);

  bool get canApply =>
      (tab == _Tab.picture ? bytes != null : fill != null) &&
      (onlyForMe || component.canChange);

  /// Messages are drawn without bubbles (Discord style).
  bool get flat => !preferences.chatBubbleLayout.value;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final shared = await component.shared();
    final own = await component.own();
    final recent = await component.recent();
    if (!mounted) return;
    setState(() {
      this.shared = shared;
      this.own = own;
      this.recent = recent;
      loading = false;
      onlyForMe = own != null || !component.canChange;
      final current = own ?? shared;
      if (current != null) _use(current);
    });
  }

  void _use(ChatWallpaper wallpaper) {
    final fill = wallpaper.fill;
    if (fill != null) {
      tab = _Tab.colors;
      colors = List.of(fill.colors);
      animate = fill.animate || !fill.canAnimate;
      base = wallpaper;
      picked = null;
      return;
    }
    tab = _Tab.picture;
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
      tab = _Tab.picture;
      picked = data;
      base = null;
      // Without bubbles, start where text stays readable.
      dim = flat ? (dark ? -0.4 : 0.4) : 0;
      blur = 0;
    });
  }

  Future<void> _apply() async {
    setState(() => busy = true);
    await ErrorUtils.tryRun(context, () async {
      if (tab == _Tab.colors) {
        await component.apply(
            fill: fill, dim: 0, blur: 0, onlyForMe: onlyForMe);
      } else {
        await component.apply(
            image: picked,
            from: picked == null ? base : null,
            dim: dim,
            blur: blur,
            onlyForMe: onlyForMe);
      }
      if (mounted) Navigator.of(context).pop();
    });
    if (mounted) setState(() => busy = false);
  }

  Future<void> _remove() async {
    setState(() => busy = true);
    await ErrorUtils.tryRun(context, () async {
      if (onlyForMe) {
        await component.removeOwn();
      } else {
        await component.remove();
      }
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

  Future<void> _editColor(int index) async {
    final adding = index >= colors.length;
    final before = List.of(colors);
    setState(() {
      if (adding) colors.add(colors.isEmpty ? Colors.teal : colors.last);
    });
    var removed = false;
    await AdaptiveDialog.show(
      context,
      title: ChatWallpaperEditor.chatWallpaperPickColor,
      builder: (context) => Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 320,
            child: ThemeColorPicker(
              initial: colors[index],
              palette: [
                for (final preset in ChatWallpaperEditor.presets) ...preset
              ],
              onChanged: (c) => setState(() => colors[index] = c),
            ),
          ),
          const SizedBox(height: 8),
          Row(mainAxisSize: MainAxisSize.min, children: [
            if (before.length > 1 && !adding)
              TextButton(
                onPressed: () {
                  removed = true;
                  Navigator.of(context).pop();
                },
                child: Text(ChatWallpaperEditor.chatWallpaperRemoveColor),
              ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(ChatWallpaperEditor.chatWallpaperSelectDone),
            ),
          ]),
        ],
      ),
    );
    if (!mounted) return;
    setState(() {
      if (removed) colors.removeAt(index);
      base = null;
    });
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
    final hasRemovable = onlyForMe ? own != null : shared != null && canChange;
    return SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          Row(children: [
            Expanded(
              child: SegmentedButton<_Tab>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                      value: _Tab.picture,
                      icon: const Icon(Icons.image_outlined),
                      label: Text(ChatWallpaperEditor.chatWallpaperTabPicture)),
                  ButtonSegment(
                      value: _Tab.colors,
                      icon: const Icon(Icons.gradient),
                      label: Text(ChatWallpaperEditor.chatWallpaperTabColors)),
                ],
                selected: {tab},
                onSelectionChanged: busy
                    ? null
                    : (s) => setState(() {
                          tab = s.first;
                          if (tab == _Tab.colors && colors.isEmpty) {
                            colors = List.of(ChatWallpaperEditor.presets.first);
                          }
                        }),
              ),
            ),
            if (tab == _Tab.picture) ...[
              const SizedBox(width: 8),
              TextButton.icon(
                  onPressed: busy ? null : _pick,
                  icon: const Icon(Icons.upload),
                  label: Text(ChatWallpaperEditor.chatWallpaperUploadImage)),
            ],
          ]),
          _preview(context),
          if (tab == _Tab.picture && bytes != null) ...[
            _slider(ChatWallpaperEditor.chatWallpaperDarkerLighter, dim, -1,
                (v) => setState(() => dim = v)),
            _slider(ChatWallpaperEditor.chatWallpaperBlur, blur, 0,
                (v) => setState(() => blur = v)),
          ],
          if (tab == _Tab.colors) _colors(context),
          if (recent.isNotEmpty) _recent(context),
          _whoSees(context),
          Row(
            children: [
              if (hasRemovable)
                TextButton(
                    onPressed: busy ? null : _remove,
                    style: TextButton.styleFrom(
                        foregroundColor: Theme.of(context).colorScheme.error),
                    child: Text(onlyForMe
                        ? ChatWallpaperEditor.chatWallpaperRemoveOwn
                        : ChatWallpaperEditor.chatWallpaperRemove)),
              const Spacer(),
              TextButton(
                  onPressed: busy ? null : () => Navigator.of(context).pop(),
                  child: Text(CommonStrings.promptCancel)),
              const SizedBox(width: 8),
              FilledButton(
                  onPressed: busy || !canApply ? null : _apply,
                  child: Text(CommonStrings.promptApply)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _whoSees(BuildContext context) {
    final canChange = component.canChange;
    final String note;
    if (onlyForMe) {
      note = tab == _Tab.picture && component.room.isE2EE
          ? "${ChatWallpaperEditor.chatWallpaperOnlyForMeNote} ${ChatWallpaperEditor.chatWallpaperOnlyForMeServerNote}"
          : ChatWallpaperEditor.chatWallpaperOnlyForMeNote;
    } else {
      note = component.isOneToOne
          ? ChatWallpaperEditor.chatWallpaperAppliesToBoth
          : ChatWallpaperEditor.chatWallpaperAppliesToEveryone;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: [
        SegmentedButton<bool>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(
                value: false,
                enabled: canChange,
                label: Text(component.isOneToOne
                    ? ChatWallpaperEditor.chatWallpaperForBoth
                    : ChatWallpaperEditor.chatWallpaperForEveryone)),
            ButtonSegment(
                value: true,
                label: Text(ChatWallpaperEditor.chatWallpaperOnlyForMe)),
          ],
          selected: {onlyForMe},
          onSelectionChanged:
              busy ? null : (s) => setState(() => onlyForMe = s.first),
        ),
        if (!canChange)
          tiamat.Text.labelLow(ChatWallpaperEditor.chatWallpaperCantChange),
        tiamat.Text.labelLow(note),
      ],
    );
  }

  Widget _colors(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fill = this.fill;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final preset in ChatWallpaperEditor.presets)
            _swatch(context, preset),
        ]),
        Row(children: [
          for (var i = 0; i < colors.length; i++)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: busy ? null : () => _editColor(i),
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                      color: colors[i],
                      shape: BoxShape.circle,
                      border: Border.all(color: scheme.outline)),
                ),
              ),
            ),
          if (colors.length < WallpaperFill.maxColors)
            IconButton(
                tooltip: ChatWallpaperEditor.chatWallpaperAddColor,
                onPressed: busy ? null : () => _editColor(colors.length),
                icon: const Icon(Icons.add_circle_outline)),
        ]),
        if (fill != null && fill.canAnimate)
          Row(children: [
            Expanded(
                child: tiamat.Text.label(
                    ChatWallpaperEditor.chatWallpaperAnimate)),
            Switch(
                value: animate,
                onChanged: busy ? null : (v) => setState(() => animate = v)),
          ]),
      ],
    );
  }

  Widget _swatch(BuildContext context, List<Color> preset) {
    final scheme = Theme.of(context).colorScheme;
    final active = listEquals(preset, colors);
    return InkWell(
      customBorder: const CircleBorder(),
      onTap: busy
          ? null
          : () => setState(() {
                colors = List.of(preset);
                base = null;
              }),
      child: Container(
        width: 40,
        height: 40,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
                color: active ? scheme.primary : Colors.transparent, width: 2)),
        child: ClipOval(
          child: ChatWallpaperView(fill: WallpaperFill(preset)),
        ),
      ),
    );
  }

  Widget _preview(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bytes = this.bytes;
    final fill = this.fill;
    final Widget? wallpaper = tab == _Tab.colors
        ? (fill != null ? ChatWallpaperView(fill: fill, flat: flat) : null)
        : (bytes != null
            ? ChatWallpaperView(
                bytes: bytes, dim: dim, blur: blur, blurScale: 0.5, flat: flat)
            : null);
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 200,
        color: scheme.surfaceContainerLow,
        child: Stack(fit: StackFit.expand, children: [
          if (wallpaper != null)
            wallpaper
          else
            Center(
                child: Padding(
              padding: const EdgeInsets.all(16),
              child:
                  tiamat.Text.labelLow(ChatWallpaperEditor.chatWallpaperNone),
            )),
          if (wallpaper != null)
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

  /// A message as the chat draws it: plain text on the wallpaper, or in a
  /// bubble when the layout uses bubbles.
  Widget _sample(BuildContext context, String text, {required bool mine}) {
    final scheme = Theme.of(context).colorScheme;
    final style = Theme.of(context)
        .textTheme
        .bodyMedium
        ?.copyWith(color: mine && !flat ? scheme.onPrimary : scheme.onSurface);
    if (!flat) {
      return Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
              color: mine ? scheme.primary : scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(12)),
          child: Text(text, style: style),
        ),
      );
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
              radius: 10,
              backgroundColor: mine ? scheme.primary : scheme.tertiary),
          const SizedBox(width: 8),
          Flexible(child: Text(text, style: style)),
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
                } else {
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
            ChatWallpaperView.of(w, blurScale: 0.2, decodeWidth: 160),
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
