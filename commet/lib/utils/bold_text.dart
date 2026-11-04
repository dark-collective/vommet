import 'package:flutter/widgets.dart';

// Vommet: the system "Bold text" accessibility setting. `Text` applies it to
// its root style only, so spans that carry their own weight (flutter_html
// message bodies, `RichText`) stay thin unless they go through this.
TextStyle? withBoldText(BuildContext context, TextStyle? style) =>
    MediaQuery.boldTextOf(context)
        ? (style ?? const TextStyle()).copyWith(fontWeight: FontWeight.bold)
        : style;
