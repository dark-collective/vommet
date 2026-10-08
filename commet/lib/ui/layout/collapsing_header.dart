import 'package:flutter/widgets.dart';

/// Vommet: a pinned header that shrinks from [maxHeight] to [minHeight] as
/// the list under it scrolls, like Discord's server banner.
class CollapsingHeaderDelegate extends SliverPersistentHeaderDelegate {
  CollapsingHeaderDelegate({
    required this.minHeight,
    required this.maxHeight,
    required this.builder,
  });

  final double minHeight;
  final double maxHeight;

  /// Builds the header at its current [height].
  final Widget Function(BuildContext context, double height) builder;

  @override
  double get minExtent => minHeight;

  @override
  double get maxExtent => maxHeight;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    final height = (maxHeight - shrinkOffset).clamp(minHeight, maxHeight);
    return SizedBox(height: height, child: builder(context, height));
  }

  @override
  bool shouldRebuild(CollapsingHeaderDelegate oldDelegate) => true;
}
