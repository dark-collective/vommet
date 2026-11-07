// Vommet: representative, inert theme-editor scenes (Vommet issue 1193).
import 'dart:async';

import 'package:commet/config/layout_style.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/atoms/message_box.dart';
import 'package:commet/ui/molecules/desktop_attachment_tray.dart';
import 'package:commet/ui/organisms/media_send_sheet/media_send_sheet.dart';
import 'package:commet/ui/organisms/unified_chat_list/unified_chat_list_preference.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/atoms/foundation.dart';
import 'package:tiamat/atoms/tile.dart';

class ThemePreviewScenes extends StatefulWidget {
  const ThemePreviewScenes(
      {required this.theme, required this.chatBuilder, super.key});
  final ThemeData theme;
  final Widget Function(LayoutOptions options) chatBuilder;

  @override
  State<ThemePreviewScenes> createState() => _ThemePreviewScenesState();
}

class _ThemePreviewScenesState extends State<ThemePreviewScenes> {
  int scene = 0;
  final subscriptions = <StreamSubscription<dynamic>>[];

  static String get chat => Intl.message('Chat',
      name: 'themePreviewChat', desc: 'Theme preview scene');
  static String get panels => Intl.message('Panels & popups',
      name: 'themePreviewPanels', desc: 'Theme preview scene');
  static String get attachments => Intl.message('Attachments',
      name: 'themePreviewAttachments', desc: 'Theme preview scene');
  static String get sample => Intl.message('Sample content · Preview only',
      name: 'themePreviewSample',
      desc: 'Theme preview examples do not perform app actions');
  static String get desktopSample => Intl.message(
      'Desktop attachment sample · Preview only',
      name: 'themePreviewDesktopAttachments',
      desc:
          'The attachment example represents the desktop tray even on a phone');
  static String get settings => Intl.message('Settings panel',
      name: 'themePreviewSettingsPanel', desc: 'Theme preview panel sample');
  static String get sounds => Intl.message('Play sounds',
      name: 'themePreviewPlaySounds', desc: 'Theme preview switch sample');
  static String get selected => Intl.message('Selected',
      name: 'themePreviewSelected', desc: 'Theme preview chip sample');
  static String get placeholder => Intl.message('Placeholder',
      name: 'themePreviewPlaceholder',
      desc: 'Theme preview highest surface sample');
  static String get sampleError => Intl.message('Could not save — sample error',
      name: 'themePreviewSampleError',
      desc: 'Theme preview static error example, not a real failure');
  static String get menu => Intl.message('Message menu',
      name: 'themePreviewMessageMenu', desc: 'Theme preview popup sample');
  static String get reply => Intl.message('Reply',
      name: 'themePreviewReply', desc: 'Theme preview menu sample');
  static String get copy => Intl.message('Copy text',
      name: 'themePreviewCopy', desc: 'Theme preview menu sample');
  static String get delete => Intl.message('Delete',
      name: 'themePreviewDelete',
      desc: 'Theme preview dangerous menu action sample');
  static String get tooltip => Intl.message('Reply to message',
      name: 'themePreviewTooltip', desc: 'Theme preview tooltip sample');
  static String get linkTitle => Intl.message('Weekend menu',
      name: 'themePreviewLinkTitle', desc: 'Theme preview link card title');
  static String get linkDescription =>
      Intl.message('A sample link preview card.',
          name: 'themePreviewLinkDescription',
          desc: 'Theme preview link card description');
  static String get message => Intl.message('Message #general',
      name: 'themePreviewMessageHint', desc: 'Theme preview composer hint');
  static String get send => Intl.message('Send',
      name: 'themePreviewSend', desc: 'Theme preview send button sample');

  @override
  void initState() {
    super.initState();
    for (final changes in <Stream<dynamic>>[
      preferences.chatBubbleLayout.onChanged,
      captionBelowMedia.onChanged,
      experimentUnifiedChatList.onChanged,
      ownBubbleSide.onChanged,
      limitMessageWidth.onChanged,
      avatarAtBottomOfGroup.onChanged,
      layoutStyleCustomPicked.onChanged,
    ]) {
      subscriptions.add(changes.listen((_) {
        if (mounted) setState(() {});
      }));
    }
  }

  @override
  void dispose() {
    for (final subscription in subscriptions) {
      subscription.cancel();
    }
    super.dispose();
  }

  Widget sampleBox(Color color, Widget child) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: widget.theme.colorScheme.outline)),
        child: child,
      );

  Widget panelSamples(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final panel = Tile(
        mode: TileType.surfaceContainer,
        child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(settings, style: Theme.of(context).textTheme.titleSmall),
                  Row(children: [
                    Expanded(child: Text(sounds)),
                    Switch(value: true, onChanged: (_) {})
                  ]),
                  Wrap(spacing: 8, children: [
                    Chip(
                        label: Text(selected),
                        backgroundColor: s.surfaceContainerHigh),
                    Chip(
                        label: Text(placeholder),
                        backgroundColor: s.surfaceContainerHighest),
                  ]),
                  const SizedBox(height: 8),
                  Row(children: [
                    Icon(Icons.error_outline, size: 18, color: s.error),
                    const SizedBox(width: 6),
                    Expanded(
                        child:
                            Text(sampleError, style: TextStyle(color: s.error)))
                  ]),
                ])));
    // Menus/tooltips are opaque, even over gradient or image backgrounds.
    final popups = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          sampleBox(
              s.surfaceContainerLowest,
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(menu, style: Theme.of(context).textTheme.titleSmall),
                for (final item in [
                  (Icons.reply, reply),
                  (Icons.copy, copy),
                  (Icons.delete_outline, delete)
                ])
                  Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(children: [
                        Icon(item.$1,
                            size: 18,
                            color: item.$1 == Icons.delete_outline
                                ? s.error
                                : Theme.of(context).iconTheme.color),
                        const SizedBox(width: 10),
                        Expanded(
                            child: Text(item.$2,
                                style: TextStyle(
                                    color: item.$1 == Icons.delete_outline
                                        ? s.error
                                        : s.onSurface))),
                      ])),
              ])),
          const SizedBox(height: 12),
          Align(
              alignment: Alignment.centerLeft,
              child: sampleBox(s.surfaceContainerLowest, Text(tooltip))),
          const SizedBox(height: 12),
          sampleBox(
              s.surfaceContainerLowest,
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(linkTitle, style: Theme.of(context).textTheme.titleSmall),
                Text(linkDescription)
              ])),
        ]);
    return LayoutBuilder(
        builder: (context, size) => size.maxWidth >= 560
            ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: panel),
                const SizedBox(width: 16),
                Expanded(child: popups)
              ])
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [panel, const SizedBox(height: 12), popups]));
  }

  Widget attachmentSamples(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    Widget toggle(String label, bool value) =>
        Row(mainAxisSize: MainAxisSize.min, children: [
          Switch(value: value, onChanged: (_) {}),
          const SizedBox(width: 6),
          Flexible(child: Text(label))
        ]);
    Widget badge(IconData icon) => Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
            color: s.surfaceContainerHighest.withAlpha(230),
            shape: BoxShape.circle),
        child: Icon(icon, size: 16, color: s.onSurface));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: s.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(
                  DesktopAttachmentTray.cornerRadius(currentLayoutStyle))),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(
                spacing: 16,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(DesktopAttachmentTray.labelCount(1)),
                  toggle(MediaSendSheet.promptRemoveHiddenInfo, true),
                  toggle(MediaSendSheet.promptSendSmaller, false),
                  TextButton(
                      onPressed: () {},
                      child: Text(DesktopAttachmentTray.promptClearAll)),
                ]),
            const SizedBox(height: 8),
            SizedBox(
                width: DesktopAttachmentTray.tileWidth,
                height: DesktopAttachmentTray.tileHeight,
                child: Stack(children: [
                  Positioned.fill(
                      child: ColoredBox(
                          color: s.surfaceContainer,
                          child: Icon(Icons.landscape_outlined,
                              size: 42, color: s.primary))),
                  Positioned(top: 0, right: 0, child: badge(Icons.close)),
                  Positioned(bottom: 0, right: 0, child: badge(Icons.crop)),
                  Positioned(
                      bottom: 0,
                      left: 0,
                      child: badge(Icons.visibility_outlined)),
                ])),
          ])),
      const SizedBox(height: 8),
      MessageBox(
          borderRadius: BorderRadius.circular(8),
          child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                Expanded(
                    child: Text(message, style: TextStyle(color: s.secondary))),
                const SizedBox(width: 8),
                FilledButton(onPressed: () {}, child: Text(send)),
              ]))),
    ]);
  }

  @override
  Widget build(BuildContext context) => Theme(
      data: widget.theme,
      child: Builder(builder: (context) {
        final options = LayoutOptions.current;
        return Material(
            type: MaterialType.transparency,
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(children: [
                        for (final (index, label)
                            in [chat, panels, attachments].indexed)
                          Padding(
                              padding:
                                  const EdgeInsets.only(right: 6, bottom: 4),
                              child: ChoiceChip(
                                  label: Text(label),
                                  selected: scene == index,
                                  onSelected: (_) =>
                                      setState(() => scene = index))),
                      ])),
                  Expanded(
                    child: scene == 0
                        ? widget.chatBuilder(options)
                        : Foundation(
                            key: const ValueKey('theme-preview-samples'),
                            child: SingleChildScrollView(
                                key: ValueKey(scene),
                                padding: const EdgeInsets.all(10),
                                child: ExcludeFocus(
                                    child: AbsorbPointer(
                                        child: scene == 1
                                            ? panelSamples(context)
                                            : attachmentSamples(context))))),
                  ),
                  Text(scene == 2 ? desktopSample : sample,
                      style: Theme.of(context).textTheme.labelSmall),
                ]));
      }));
}
