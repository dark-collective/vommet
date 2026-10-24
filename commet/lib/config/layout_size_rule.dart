// Vommet: size rule for the automatic mobile/desktop layout choice.
//
// Upstream only looked at the width, so a phone turned sideways (about
// 850 x 400 dp) got the desktop layout, cramped. The desktop layout now also
// needs the shorter side (not just the width) to be at least [desktopLayoutMinSide], the usual
// Android tablet test, so phones stay mobile in landscape and tablets keep
// the desktop layout in either orientation.

const double desktopLayoutMinSide = 600;

bool useMobileLayoutForSize(double width, double height, double appScale) {
  // The shorter side is never wider than the width, so this covers both.
  final shortestSide = width < height ? width : height;
  return shortestSide * appScale < desktopLayoutMinSide;
}
