import 'package:commet/client/room.dart';
import 'package:commet/config/app_font.dart';
import 'package:commet/config/chat_text_look.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/molecules/timeline_events/layouts/timeline_event_layout_bubble.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/ui/pages/settings/categories/app/theme_settings/theme_color_picker.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/config/style/theme_extensions.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Vommet issue 783: the "Just for you" part of a 1:1 chat's Appearance
/// settings: the chat's own message text color, font and size, on this
/// device only. A hard-to-read color gets a warning, never a block.
class ChatTextLookSettings extends StatefulWidget {
  const ChatTextLookSettings({required this.room, super.key});
  final Room room;

  @override
  State<ChatTextLookSettings> createState() => _ChatTextLookSettingsState();
}

class _ChatTextLookSettingsState extends State<ChatTextLookSettings> {
  late ChatTextLook look = ChatTextLooks.of(widget.room.localId);

  /// A low-contrast color the user chose to keep ("Use anyway").
  int? acceptedLowContrast;

  Future<void> save(ChatTextLook next) async {
    setState(() => look = next);
    await ChatTextLooks.set(widget.room.localId, next);
  }

  /// The backgrounds messages sit on: both bubble colors in the bubble
  /// layout, else the chat background. A wallpaper isn't measured; its
  /// colors vary across the picture.
  List<Color> backgrounds(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    if (!preferences.chatBubbleLayout.value) return [colors.surface];
    final extra = Theme.of(context).extension<ExtraColors>();
    return [
      for (final own in [true, false])
        Color.alphaBlend(
            TimelineEventLayoutBubble.bubbleColors(colors,
                    isOwnMessage: own, extra: extra)
                .$1,
            colors.surface),
    ];
  }

  /// The worst contrast of [color] on the message backgrounds.
  (double, Color) worstContrast(Color color, List<Color> backgrounds) {
    var worst = double.infinity;
    var on = backgrounds.first;
    for (final b in backgrounds) {
      final c = ChatTextLook.contrast(color, b);
      if (c < worst) {
        worst = c;
        on = b;
      }
    }
    return (worst, on);
  }

  void pickAnyColor(BuildContext context) {
    AdaptiveDialog.show(context,
        title: chatTextLookColor,
        builder: (context) => SizedBox(
              width: 320,
              child: ThemeColorPicker(
                initial: look.color ?? Theme.of(context).colorScheme.onSurface,
                palette: ChatTextLook.presets,
                onChanged: (c) => save(look.copyWith(color: c.withAlpha(0xFF))),
              ),
            ));
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final shownColor = look.color ?? colors.onSurface;
    final (ratio, worstOn) = worstContrast(shownColor, backgrounds(context));
    final low = look.color != null &&
        ratio < ChatTextLook.readableContrast &&
        acceptedLowContrast != look.color!.toARGB32();
    final baseSize = DefaultTextStyle.of(context).style.fontSize ?? 14;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 8,
      children: [
        Row(children: [
          tiamat.Text.labelLow(chatTextLookTitle),
          const SizedBox(width: 8),
          Expanded(child: tiamat.Text.labelLow("· $chatTextLookNote")),
          if (!look.isDefault)
            TextButton(
              onPressed: () => save(ChatTextLook.none),
              child: Text(chatTextLookReset),
            ),
        ]),
        // A sample message in the chosen look.
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: worstOn,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(chatTextLookPreview,
              style: look
                  .apply(TextStyle(fontSize: baseSize))
                  .copyWith(color: shownColor)),
        ),
        tiamat.Text.labelLow(chatTextLookColor),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _Swatch(
              color: colors.onSurface,
              label: chatTextLookDefaultColor,
              selected: look.color == null,
              onTap: () => save(look.copyWith(clearColor: true)),
            ),
            for (final c in ChatTextLook.presets)
              _Swatch(
                color: c,
                selected: look.color?.toARGB32() == c.toARGB32(),
                onTap: () => save(look.copyWith(color: c)),
              ),
            TextButton.icon(
              onPressed: () => pickAnyColor(context),
              icon: const Icon(Icons.palette_outlined, size: 18),
              label: Text(chatTextLookAnyColor),
            ),
          ],
        ),
        tiamat.Text.labelLow(chatTextLookContrast(ratio.toStringAsFixed(1))),
        if (low)
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: colors.errorContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(chatTextLookLowContrast,
                    style: TextStyle(color: colors.onErrorContainer)),
                Wrap(spacing: 8, children: [
                  TextButton(
                    onPressed: () => setState(
                        () => acceptedLowContrast = look.color!.toARGB32()),
                    child: Text(chatTextLookUseAnyway),
                  ),
                  TextButton(
                    onPressed: () => save(look.copyWith(
                        color:
                            ChatTextLook.readableNear(look.color!, worstOn))),
                    child: Text(chatTextLookPickReadable),
                  ),
                ]),
              ],
            ),
          ),
        tiamat.Text.labelLow(chatTextLookFont),
        DropdownButton<String>(
          value: look.fontId,
          isExpanded: true,
          items: [
            DropdownMenuItem(
                value: AppFont.defaultId, child: Text(chatTextLookAppFont)),
            for (final f in AppFont.bundled)
              DropdownMenuItem(
                  value: f.id,
                  child: Text(f.name, style: TextStyle(fontFamily: f.family))),
          ],
          onChanged: (id) {
            if (id != null) save(look.copyWith(fontId: id));
          },
        ),
        Row(children: [
          tiamat.Text.labelLow(chatTextLookSize),
          Expanded(
            child: Slider(
              value: look.scale,
              min: ChatTextLook.minScale,
              max: ChatTextLook.maxScale,
              divisions: 14,
              label: "${(look.scale * 100).round()}%",
              onChanged: (v) => setState(() => look = look.copyWith(scale: v)),
              onChangeEnd: (v) => save(look.copyWith(scale: v)),
            ),
          ),
          SizedBox(
              width: 48,
              child: tiamat.Text.labelLow("${(look.scale * 100).round()}%")),
        ]),
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch(
      {required this.color,
      required this.selected,
      required this.onTap,
      this.label});
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Tooltip(
      message: label ?? "",
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
                color: selected ? colors.primary : colors.outlineVariant,
                width: selected ? 3 : 1),
          ),
          child: label == null
              ? null
              : Icon(Icons.format_color_reset, size: 16, color: colors.surface),
        ),
      ),
    );
  }
}
