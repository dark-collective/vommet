import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

// Vommet: a Flutter copy of the platform splash (same purple and logo) with a
// random message under it. It is shown from the first frame until the app is
// ready, so it takes over from the platform splash without a visible change.
class SplashPage extends StatelessWidget {
  const SplashPage({required this.message, super.key});

  final String message;

  static const Color background = Color(0xFF2B1B6B);
  static const Color messageColor = Color(0xB8E8E2FF);

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
            Center(
              child: SvgPicture.asset(
                "assets/images/app_icon/icon.svg",
                width: iconSize,
                height: iconSize,
              ),
            ),
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
