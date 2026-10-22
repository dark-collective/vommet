import 'package:flutter/material.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart';

@UseCase(name: 'Default', type: Avatar)
Widget wbavatarDefault(BuildContext context) {
  return const Center(
      child: Avatar(
    image: AssetImage("assets/images/placeholder/generic/checker_purple.png"),
  ));
}

@UseCase(name: 'Large', type: Avatar)
Widget wbavatarLarge(BuildContext context) {
  return const Center(
      child: Avatar.large(
    image: AssetImage("assets/images/placeholder/generic/checker_purple.png"),
  ));
}

@UseCase(name: 'Placeholder', type: Avatar)
Widget wbavatarPlaceholder(BuildContext context) {
  return const Center(
      child: Avatar(
    placeholderText: "A",
  ));
}

@UseCase(name: 'Placeholder Large', type: Avatar)
Widget wbavatarPlaceholderLarge(BuildContext context) {
  return const Center(
      child: Avatar.large(
    placeholderText: "A",
  ));
}

class Avatar extends StatelessWidget {
  const Avatar(
      {Key? key,
      this.image,
      this.radius = 22,
      this.placeholderText,
      this.placeholderColor,
      this.border,
      this.isPadding = false})
      : super(key: key);

  const Avatar.small({
    Key? key,
    this.image,
    this.placeholderText,
    this.placeholderColor,
    this.border,
    this.isPadding = false,
  })  : radius = 15,
        super(key: key);

  const Avatar.medium(
      {Key? key,
      required this.image,
      this.placeholderText,
      this.placeholderColor,
      this.border,
      this.isPadding = false})
      : radius = 22,
        super(key: key);

  const Avatar.large(
      {Key? key,
      this.image,
      this.placeholderText,
      this.placeholderColor,
      this.border,
      this.isPadding = false})
      : radius = 44,
        super(key: key);

  const Avatar.extraLarge(
      {Key? key,
      this.image,
      this.placeholderText,
      this.placeholderColor,
      this.border,
      this.isPadding = false})
      : radius = 80,
        super(key: key);

  final double radius;
  final ImageProvider? image;
  final String? placeholderText;
  final Color? placeholderColor;
  final BoxBorder? border;
  final bool isPadding;

  @override
  Widget build(BuildContext context) {
    if (isPadding) {
      return SizedBox(
        width: radius * 2,
        height: 1,
      );
    }

    if (image != null) {
      return SizedBox(
        width: radius * 2,
        height: radius * 2,
        child: DecoratedBox(
            decoration: BoxDecoration(
              border: border,
              borderRadius: BorderRadius.circular(radius / 1.25),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(radius / 1.25),
              // Keyed by the provider so a reused row never keeps the
              // previous user's avatar while this one loads, and the
              // placeholder shows until the image arrives (or if it never
              // does / fails), instead of an empty box.
              child: Image(
                key: ValueKey(image),
                image: image!,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.medium,
                frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                  if (wasSynchronouslyLoaded) return child;
                  if (frame == null) return buildPlaceholder(context);
                  return TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: 1),
                    duration: Durations.short2,
                    builder: (context, opacity, child) =>
                        Opacity(opacity: opacity, child: child),
                    child: child,
                  );
                },
                errorBuilder: (context, error, stackTrace) =>
                    buildPlaceholder(context),
              ),
            )),
      );
    }

    return SizedBox(
      width: radius * 2,
      height: radius * 2,
      child: buildPlaceholder(context, border: border),
    );
  }

  Widget buildPlaceholder(BuildContext context, {BoxBorder? border}) {
    if (placeholderText == null) return const SizedBox.shrink();

    return DecoratedBox(
      decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius / 1.25),
          color: placeholderColor ?? Colors.transparent,
          border: border),
      child: Align(
          alignment: Alignment.center,
          child: placeholderText!.isNotEmpty
              ? Text(
                  placeholderText!.characters.first.toUpperCase(),
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall!
                      .copyWith(fontSize: radius),
                )
              : null),
    );
  }
}
