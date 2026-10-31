import 'dart:math';

import 'package:commet/config/app_icon_design.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

// Vommet: a Flutter copy of the platform splash (same purple and logo) with a
// random message under it. It is shown from the first frame until the app is
// ready, so it takes over from the platform splash without a visible change.
// The logo is the design picked for the splash screen (Vommet issue 591).
class SplashPage extends StatelessWidget {
  const SplashPage({required this.message, super.key});

  final String message;

  static const Color background = Color(0xFF2B1B6B);
  static const Color messageColor = Color(0xB8E8E2FF);

  /// The logo picked for the splash screen; an uploaded one (Vommet issue
  /// 681) falls back to the V if it can't be read.
  Widget _icon(double size) {
    final design = splashIconDesign;
    final file =
        design == AppIconDesign.custom ? AppIconPlace.splash.customFile : null;
    final svg = SvgPicture.asset(design.svgAsset, width: size, height: size);
    if (file == null) return svg;
    return Image.file(file,
        width: size, height: size, errorBuilder: (_, __, ___) => svg);
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.maybeOf(context) ??
        MediaQueryData.fromView(View.of(context));
    final size = media.size;
    final iconSize = min(size.shortestSide * 0.34, 160.0);
    final narrow = size.width < 600;

    return Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: background,
        child: Stack(
          children: [
            Center(child: _icon(iconSize)),
            Positioned(
              left: size.width * (narrow ? 0.09 : 0.14),
              right: size.width * (narrow ? 0.09 : 0.14),
              bottom: media.viewPadding.bottom + size.height * 0.07,
              // A message with line breaks is a list: its lines share one
              // left edge, and the block stays centred under the logo.
              child: Center(
                child: Text(
                  message,
                  textAlign: message.contains("\n")
                      ? TextAlign.left
                      : TextAlign.center,
                  textWidthBasis: TextWidthBasis.longestLine,
                  style: const TextStyle(
                    fontFamily: "NunitoSans",
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    height: 1.4,
                    color: messageColor,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
