// Vommet: how big pictures are in the timeline (Vommet issue 721).
// Kept beside the feature, not in preferences.dart, so this topic doesn't
// touch a file most topics edit.
import 'dart:math';
import 'dart:ui';

import 'package:commet/config/preferences/string_preference.dart';
import 'package:intl/intl.dart';

enum TimelineImageSize {
  /// Pictures up to 200 px tall and 500 px wide (the usual size).
  standard,

  /// Pictures up to the width of the timeline, never taller than most of
  /// the window.
  large;

  static TimelineImageSize parse(String value) =>
      values.where((s) => s.name == value).firstOrNull ?? standard;

  String get label => switch (this) {
        standard => timelineImageSizeDefault,
        large => timelineImageSizeLarge,
      };

  String get description => switch (this) {
        standard => timelineImageSizeDefaultDescription,
        large => timelineImageSizeLargeDescription,
      };

  /// Largest size of one picture or video preview in a window of [window]
  /// size. An infinite width means as wide as the timeline allows.
  Size maxPictureSize(Size window) => switch (this) {
        standard => const Size(500, 200),
        large =>
          Size(double.infinity, max(200, window.height * heightShare(window))),
      };

  /// How much of the window's height a large picture may take: less on a
  /// phone held upright, so the text around it stays in view.
  static double heightShare(Size window) =>
      window.width < window.height ? 0.6 : 0.75;

  /// Widest a picture mosaic gets; infinite = as wide as the timeline.
  double get maxMosaicWidth => this == large ? double.infinity : 500;

  /// How much taller a mosaic's rows are than at the usual size.
  double get mosaicRowScale => this == large ? 1.8 : 1;

  /// Width a picture's thumbnail has to cover before the full picture is
  /// loaded instead, so large pictures stay sharp.
  double get sharpWidth => this == large ? 1000 : 500;
}

final StringPreference timelineImageSizePreference = StringPreference(
    "vommet_timeline_image_size",
    defaultValue: TimelineImageSize.standard.name);

TimelineImageSize get timelineImageSize =>
    TimelineImageSize.parse(timelineImageSizePreference.value);

String get timelineImageSizeTitle => Intl.message("Image size in the timeline",
    name: "timelineImageSizeTitle",
    desc: "Title of the setting that picks how big pictures are in the chat");

String get timelineImageSizeSettingsDescription =>
    Intl.message("Pictures, picture mosaics and video previews in every room.",
        name: "timelineImageSizeSettingsDescription",
        desc: "Explains the image size setting in Settings › Appearance");

String get timelineImageSizeDefault => Intl.message("Default",
    name: "timelineImageSizeDefault",
    desc: "Image size option: the usual, smaller pictures");

String get timelineImageSizeLarge => Intl.message("Large",
    name: "timelineImageSizeLarge",
    desc: "Image size option: much bigger pictures in the chat");

String get timelineImageSizeDefaultDescription =>
    Intl.message("Small pictures, so more messages fit on screen.",
        name: "timelineImageSizeDefaultDescription",
        desc: "Describes the Default image size option");

String get timelineImageSizeLargeDescription => Intl.message(
    "Pictures as wide as the chat, never taller than most of the window.",
    name: "timelineImageSizeLargeDescription",
    desc: "Describes the Large image size option");
