import 'package:intl/intl.dart';

class RoomCreationStrings {
  static String get labelCreateRoom =>
      Intl.message("Create Room", name: "labelCreateRoom");

  static String get labelPickExistingRoom => Intl.message(
        "Existing Room",
        name: "labelPickExistingRoom",
      );

  static String get labelJoinRoom => Intl.message(
        "Join Room",
        name: "labelJoinRoom",
      );

  static String get labelRoomTypeTextChat => Intl.message("Text Chat",
      name: "labelRoomTypeTextChat",
      desc: "Label for creating a regular text based chat room");

  static String get labelRoomTypeVoiceChat => Intl.message(
        "Voice Chat",
        name: "labelRoomTypeVoiceChat",
      );

  static String get labelRoomTypePhotoAlbum => Intl.message(
        "Photo Album",
        name: "labelRoomTypePhotoAlbum",
      );

  static String get labelRoomTypeCalendar => Intl.message(
        "Calendar",
        name: "labelRoomTypeCalendar",
      );

  static String get labelRoomTypeSpace => Intl.message(
        "Space",
        name: "labelRoomTypeSpace",
      );

  static String get labelNotInAnySpace => Intl.message("Not in any space",
      name: "labelNotInAnySpace",
      desc:
          "Filter chip when adding an existing room to a space: shows only rooms that aren't in any of your spaces");

  static String get tooltipNotInAnySpace => Intl.message(
      "Only show rooms that aren't in any of your spaces yet",
      name: "tooltipNotInAnySpace",
      desc:
          "Tooltip of the 'Not in any space' filter chip when adding an existing room to a space");

  static String get labelHideDirectMessages => Intl.message("Hide DMs",
      name: "labelHideDirectMessages",
      desc:
          "Filter chip when adding an existing room to a space: leaves direct messages out of the list (on by default)");

  static String get tooltipHideDirectMessages => Intl.message(
      "Don't show direct messages in the list",
      name: "tooltipHideDirectMessages",
      desc:
          "Tooltip of the 'Hide DMs' filter chip when adding an existing room to a space");
}
