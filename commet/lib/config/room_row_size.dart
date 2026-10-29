// Vommet: how big each room row is in the room lists and the Share to…
// picker (Vommet issue 796). Large rows are easier to tap: taller, with a
// bigger picture and name and a gap between rows, as on Telegram. The
// server and space rail is not affected.
import 'package:commet/config/preferences/string_preference.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

enum RoomRowSize {
  /// The usual rows.
  standard,

  /// Taller rows with a bigger picture and name.
  large;

  static RoomRowSize parse(String value) =>
      values.where((s) => s.name == value).firstOrNull ?? standard;

  String get label => switch (this) {
        standard => roomRowSizeStandard,
        large => roomRowSizeLarge,
      };

  String get description => switch (this) {
        standard => roomRowSizeStandardDescription,
        large => roomRowSizeLargeDescription,
      };

  bool get isLarge => this == large;

  /// Height of a one-line room row in the sidebar (Discord-style list).
  double get sidebarRowHeight => isLarge ? 48 : 37;

  /// Radius of a room's picture in the sidebar.
  double get sidebarAvatarRadius => isLarge ? 16 : 12;

  /// Radius of a room's picture in a chat list row.
  double get panelAvatarRadius => isLarge ? 23 : 17;

  /// Radius of a room's picture in the Share to… picker.
  double get shareAvatarRadius => isLarge ? 28 : 22;

  /// Padding inside a row.
  EdgeInsets get rowPadding => isLarge
      ? const EdgeInsets.symmetric(horizontal: 4, vertical: 6)
      : const EdgeInsets.all(2);

  /// Gap between rows.
  double get rowGap => isLarge ? 4 : 0;

  /// How much bigger the row's text is.
  double get textScale => isLarge ? 1.15 : 1;

  /// [base] times [textScale].
  TextScaler textScaler(TextScaler base) =>
      isLarge ? TextScaler.linear(base.scale(100) / 100 * textScale) : base;
}

final StringPreference roomRowSizePreference = StringPreference(
    "vommet_room_row_size",
    defaultValue: RoomRowSize.standard.name);

RoomRowSize get roomRowSize => RoomRowSize.parse(roomRowSizePreference.value);

String get roomRowSizeTitle => Intl.message("Room row size",
    name: "roomRowSizeTitle",
    desc: "Title of the setting for how big room rows are in room lists");

String get roomRowSizeDescription => Intl.message(
    "How big each room is in your room lists and the Share to… picker. Large rows are easier to tap.",
    name: "roomRowSizeDescription",
    desc: "Explains the room row size setting in Settings › Appearance");

String get roomRowSizeStandard => Intl.message("Standard",
    name: "roomRowSizeStandard",
    desc: "Room row size option: the usual room rows");

String get roomRowSizeLarge => Intl.message("Large",
    name: "roomRowSizeLarge",
    desc: "Room row size option: taller room rows, easier to tap");

String get roomRowSizeStandardDescription =>
    Intl.message("More rooms fit on screen",
        name: "roomRowSizeStandardDescription",
        desc: "Under the Standard room row size option");

String get roomRowSizeLargeDescription =>
    Intl.message("Taller rows, bigger pictures and names",
        name: "roomRowSizeLargeDescription",
        desc: "Under the Large room row size option");
