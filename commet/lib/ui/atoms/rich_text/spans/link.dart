import 'package:commet/utils/links/link_utils.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tiamat/config/style/theme_extensions.dart';

class LinkSpan {
  static InlineSpan create(String text,
      {required BuildContext context,
      required String clientId,
      destination,
      TextStyle? style}) {
    var color = Theme.of(context).extension<ExtraColors>()?.linkColor ??
        Theme.of(context).colorScheme.primary;

    final target = destination?.toString() ?? "";

    return TextSpan(
        text: text,
        style: (style ?? const TextStyle())
            .copyWith(color: color, decorationColor: color),
        recognizer: LinkGestureRecognizer()
          ..onTap = () {
            if (destination != null) {
              LinkUtils.open(destination, clientId: clientId, context: context);
            }
          }
          ..onLongPress = target.isEmpty
              ? null
              : () {
                  // Vommet issue 690: a touch long-press on the link copies
                  // its target, with the usual long-press feedback.
                  Clipboard.setData(ClipboardData(text: target));
                  if (context.mounted) Feedback.forLongPress(context);
                });
  }
}

/// Vommet: a link's tap plus a touch-only long-press (Vommet issue 690). A
/// [TextSpan] takes one recognizer, so this tap recognizer also enters a
/// [LongPressGestureRecognizer] into the arena for each touch. The span is
/// hit first, so its long-press timer fires before the message's own
/// long-press and wins; a long-press anywhere else on the message, mouse
/// input and taps behave as before. Staying a [TapGestureRecognizer] keeps
/// the link's semantics tap and pointer cursor.
class LinkGestureRecognizer extends TapGestureRecognizer {
  LinkGestureRecognizer();

  late final LongPressGestureRecognizer _longPress = LongPressGestureRecognizer(
      supportedDevices: const {
        PointerDeviceKind.touch,
        PointerDeviceKind.stylus
      })
    ..onLongPress = () => onLongPress?.call();

  VoidCallback? onLongPress;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    if (onLongPress != null) _longPress.addPointer(event);
  }

  @override
  void dispose() {
    _longPress.dispose();
    super.dispose();
  }
}
