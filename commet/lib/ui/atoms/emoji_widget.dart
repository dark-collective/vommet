import 'package:commet/client/components/emoticon/emoticon.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

// ignore: must_be_immutable
class EmojiWidget extends StatelessWidget {
  final Emoticon emoji;
  double height;
  EdgeInsetsGeometry padding;

  /// Caps the width of a text reaction (one without an image) and shortens
  /// long text, so it can't push other reactions out of a row (Vommet issue
  /// 643).
  double? maxWidth;

  /// Text reactions longer than this many characters are cut short when
  /// [maxWidth] is set.
  static const maxTextLength = 10;

  EmojiWidget(this.emoji,
      {super.key,
      this.height = 24,
      this.maxWidth,
      this.padding = const EdgeInsetsGeometry.all(0)});

  static String shortenText(String text) {
    var chars = text.characters;
    if (chars.length <= maxTextLength) return text;
    return "${chars.take(maxTextLength - 1)}\u2026";
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
        padding: const EdgeInsets.fromLTRB(2, 0, 2, 0),
        child: emoji.image != null
            ? SizedBox(
                width: height,
                height: height,
                child: FadeInImage(
                  placeholder: tiamat.transparentImage.image,
                  fadeInDuration: Durations.medium1,
                  filterQuality: FilterQuality.medium,
                  fit: BoxFit.contain,
                  width: height,
                  height: height,
                  image: emoji.image!,
                ),
              )
            : ConstrainedBox(
                constraints:
                    BoxConstraints(maxWidth: maxWidth ?? double.infinity),
                child: SizedBox(
                  height: height,
                  child: FittedBox(
                    fit: BoxFit.contain,
                    child: Padding(
                      padding: padding,
                      child: Text(
                        maxWidth == null ? emoji.slug : shortenText(emoji.slug),
                      ),
                    ),
                  ),
                ),
              ));
  }
}
