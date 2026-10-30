import 'package:commet/client/client.dart';
import 'package:commet/client/components/chat_wallpaper/chat_wallpaper_component.dart';
import 'package:commet/ui/organisms/chat_wallpaper/chat_wallpaper_editor.dart';
import 'package:commet/ui/pages/settings/categories/app/boolean_toggle.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Vommet issue 746: the chat wallpaper part of a chat's room settings
/// (Appearance): open the editor, go back from your own wallpaper to the
/// shared one, and hide the wallpaper for yourself.
class ChatWallpaperRoomSettings extends StatelessWidget {
  const ChatWallpaperRoomSettings({required this.room, super.key});
  final Room room;

  static String get chatWallpaperChange => Intl.message("Change wallpaper…",
      name: "chatWallpaperChange",
      desc:
          "Button in a chat's Appearance settings that opens the chat wallpaper dialog");

  static String get chatWallpaperShowHere => Intl.message(
      "Show wallpaper in this chat",
      name: "chatWallpaperShowHere",
      desc:
          "Switch in a chat's Appearance settings; off hides the wallpaper for you only");

  static String get chatWallpaperShowHereDescription =>
      Intl.message("Only for you, on all your devices. No one else is told.",
          name: "chatWallpaperShowHereDescription",
          desc: "Explanation under the \"Show wallpaper in this chat\" switch");

  static String get chatWallpaperOwnSet => Intl.message(
      "You set a wallpaper only you see here.",
      name: "chatWallpaperOwnSet",
      desc:
          "Shown in a chat's Appearance settings while you use your own wallpaper instead of the chat's shared one");

  static String get chatWallpaperUseShared => Intl.message("Use the shared one",
      name: "chatWallpaperUseShared",
      desc:
          "Button in a 1:1 chat's Appearance settings that drops your own wallpaper so the one you both see shows again");

  static String get chatWallpaperUseGroups => Intl.message("Use the group's",
      name: "chatWallpaperUseGroups",
      desc:
          "Button in a group's Appearance settings that drops your own wallpaper so the group's wallpaper shows again");

  @override
  Widget build(BuildContext context) {
    final component = ChatWallpaperEditor.availableIn(room);
    if (component == null) return const SizedBox.shrink();
    return StreamBuilder(
      stream: component.onChanged,
      builder: (context, _) => _build(context, component),
    );
  }

  Widget _build(BuildContext context, ChatWallpaperComponent component) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 8,
      children: [
        tiamat.Text.labelLow(ChatWallpaperEditor.chatWallpaperTitle),
        tiamat.Button(
          text: chatWallpaperChange,
          onTap: () => ChatWallpaperEditor.show(context, component),
        ),
        if (component.hasOwn)
          Row(children: [
            Expanded(child: tiamat.Text.labelLow(chatWallpaperOwnSet)),
            TextButton(
              onPressed: () => component.removeOwn(),
              child: Text(component.isOneToOne
                  ? chatWallpaperUseShared
                  : chatWallpaperUseGroups),
            ),
          ]),
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
        "Switch in Settings › Appearance that shows or hides chat wallpapers");

String get labelShowChatWallpapersDescription => Intl.message(
    "Show the wallpapers set in your chats and groups. Off hides them on this device; you can still set one.",
    name: "labelShowChatWallpapersDescription",
    desc: "Explanation under the \"Show chat wallpapers\" switch");
