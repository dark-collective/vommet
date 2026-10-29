import 'package:commet/client/client.dart';
import 'package:commet/ui/organisms/chat_wallpaper/chat_wallpaper_editor.dart';
import 'package:commet/ui/pages/settings/categories/app/boolean_toggle.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Vommet issue 746: the chat wallpaper part of a 1:1 chat's room settings
/// (Appearance): open the editor, and hide the wallpaper for yourself.
class ChatWallpaperRoomSettings extends StatelessWidget {
  const ChatWallpaperRoomSettings({required this.room, super.key});
  final Room room;

  static String get chatWallpaperChange => Intl.message("Change wallpaper…",
      name: "chatWallpaperChange",
      desc:
          "Button in a 1:1 chat's Appearance settings that opens the chat wallpaper dialog");

  static String get chatWallpaperShowHere => Intl.message(
      "Show wallpaper in this chat",
      name: "chatWallpaperShowHere",
      desc:
          "Switch in a 1:1 chat's Appearance settings; off hides the shared wallpaper for you only");

  static String get chatWallpaperShowHereDescription => Intl.message(
      "Only for you, on all your devices. The other person isn't told.",
      name: "chatWallpaperShowHereDescription",
      desc: "Explanation under the \"Show wallpaper in this chat\" switch");

  @override
  Widget build(BuildContext context) {
    final component = ChatWallpaperEditor.availableIn(room);
    if (component == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 8,
      children: [
        tiamat.Text.labelLow(ChatWallpaperEditor.chatWallpaperTitle),
        tiamat.Button(
          text: chatWallpaperChange,
          onTap: () => ChatWallpaperEditor.show(context, component),
        ),
        BooleanToggle(
          getValue: () => !component.hiddenHere,
          setValue: (value) => component.setHiddenHere(!value),
          title: chatWallpaperShowHere,
          description: chatWallpaperShowHereDescription,
        ),
      ],
    );
  }
}

/// Settings › Appearance: show chat wallpapers at all, while the experiment
/// is on.
String get labelShowChatWallpapers => Intl.message("Show chat wallpapers",
    name: "labelShowChatWallpapers",
    desc:
        "Switch in Settings › Appearance that shows or hides 1:1 chat wallpapers");

String get labelShowChatWallpapersDescription => Intl.message(
    "Show the wallpaper you or the other person set in a 1:1 chat. Off hides them on this device; you can still set one.",
    name: "labelShowChatWallpapersDescription",
    desc: "Explanation under the \"Show chat wallpapers\" switch");
