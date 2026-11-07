// Vommet issue 1069: the one local shortcut is separate from global call keys.
import 'package:commet/main.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/utils/common_strings.dart';
import 'package:commet/utils/hover_reply_binding.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class HoverReplySettings extends StatelessWidget {
  const HoverReplySettings({super.key});
  static String get section => Intl.message('In-app shortcuts',
      name: 'hoverReplySection', desc: 'Settings section for local shortcuts');
  static String get description => Intl.message(
      'Works while Vommet is focused. Hover a message, then press your shortcut.',
      name: 'hoverReplyDescription',
      desc: 'Local reply shortcut help');
  static String get unset => Intl.message('Not set',
      name: 'hoverReplyUnset', desc: 'No reply shortcut assigned');
  static String get setKey => Intl.message('Set shortcut',
      name: 'hoverReplySetKey', desc: 'Configure the reply shortcut');
  static String get change => Intl.message('Change shortcut',
      name: 'hoverReplyChange', desc: 'Rebind reply shortcut');
  static String get clear => Intl.message('Clear',
      name: 'hoverReplyClear', desc: 'Remove reply shortcut');
  static String get save =>
      Intl.message('Save', name: 'hoverReplySave', desc: 'Save reply shortcut');
  static String get captureTitle => Intl.message('Set reply shortcut',
      name: 'hoverReplyCaptureTitle', desc: 'Reply key capture dialog title');
  static String get pressKey =>
      Intl.message('Press a key combination. Escape cancels.',
          name: 'hoverReplyPressKey', desc: 'Reply key recorder instructions');

  @override
  Widget build(BuildContext context) => StreamBuilder(
      stream: preferences.onSettingChanged,
      builder: (context, _) {
        final key = HoverReplyBinding.saved;
        return tiamat.Panel(
            header: section,
            mode: tiamat.TileType.surfaceContainerLow,
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 8,
                children: [
                  tiamat.Text(HoverReplyBinding.title),
                  tiamat.Text.labelLow(description),
                  tiamat.Text(key?.label ?? unset),
                  if (key?.invalidReason case final reason?)
                    tiamat.Text.labelLow(reason),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    tiamat.Button.secondary(
                        text: key == null ? setKey : change,
                        onTap: () => HoverReplyBinding.capture(() =>
                            AdaptiveDialog.show<void>(context,
                                builder: (_) => const _Capture()))),
                    if (key != null)
                      tiamat.Button.secondary(
                          text: clear,
                          onTap: () => preferences.hoverReplyKey.reset()),
                  ]),
                ]));
      });
}

class _Capture extends StatefulWidget {
  const _Capture();
  @override
  State<_Capture> createState() => _CaptureState();
}

class _CaptureState extends State<_Capture> {
  HoverReplyBinding? candidate;
  @override
  Widget build(BuildContext context) => Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (!node.hasPrimaryFocus || event.logicalKey == LogicalKeyboardKey.tab)
          return KeyEventResult.ignored;
        if (event is! KeyDownEvent) return KeyEventResult.handled;
        if (event.logicalKey == LogicalKeyboardKey.escape) {
          Navigator.of(context).pop();
        } else if (!{
          LogicalKeyboardKey.controlLeft,
          LogicalKeyboardKey.controlRight,
          LogicalKeyboardKey.shiftLeft,
          LogicalKeyboardKey.shiftRight,
          LogicalKeyboardKey.altLeft,
          LogicalKeyboardKey.altRight,
          LogicalKeyboardKey.metaLeft,
          LogicalKeyboardKey.metaRight
        }.contains(event.logicalKey)) {
          setState(() => candidate = HoverReplyBinding.fromEvent(event));
        }
        return KeyEventResult.handled;
      },
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 12,
          children: [
            tiamat.Text.largeTitle(HoverReplySettings.captureTitle),
            tiamat.Text(HoverReplySettings.pressKey),
            tiamat.Text(candidate?.label ?? HoverReplySettings.unset),
            if (candidate?.invalidReason case final reason?)
              tiamat.Text.labelLow(reason),
            Wrap(spacing: 8, runSpacing: 8, children: [
              tiamat.Button(
                  text: HoverReplySettings.save,
                  onTap: candidate == null || candidate!.invalidReason != null
                      ? null
                      : () async {
                          await candidate!.save();
                          if (context.mounted) Navigator.of(context).pop();
                        }),
              tiamat.Button.secondary(
                  text: CommonStrings.promptCancel,
                  onTap: () => Navigator.of(context).pop()),
            ]),
          ]));
}
