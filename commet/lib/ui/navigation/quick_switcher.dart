import 'package:collection/collection.dart';
import 'package:commet/client/components/direct_messages/direct_message_component.dart';
import 'package:commet/client/room.dart';
import 'package:commet/client/room_replacement.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/atoms/redaction_scope.dart';
import 'package:commet/ui/atoms/room_panel_view.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/ui/navigation/vommet_quick_switcher_rank.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:commet/utils/redaction/redaction_preferences.dart';
import 'package:commet/utils/redaction/redaction_toggle.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/atoms/tile.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class QuickSwitcher extends StatefulWidget {
  const QuickSwitcher({super.key});

  static bool isShowing = false;

  static Future<void> show(BuildContext context) async {
    if (!isShowing) {
      isShowing = true;

      await AdaptiveDialog.show(
        context,
        builder: (context) {
          return QuickSwitcher();
        },
      );

      isShowing = false;
    }
  }

  @override
  State<QuickSwitcher> createState() => _QuickSwitcherState();
}

abstract class QuickSwitcherSearchItem {
  String get searchEntry;

  String get id;

  void onTap(BuildContext context);

  Widget build(BuildContext context);
}

class QuickSwitcherSearchItemRoom implements QuickSwitcherSearchItem {
  Room room;

  @override
  String id;

  QuickSwitcherSearchItemRoom(this.room, {required this.id});

  @override
  String get searchEntry => room.displayName;

  @override
  Widget build(BuildContext context) {
    return quickSwitcherRoomPanel(context, room, onTap: () => onTap(context));
  }

  @override
  void onTap(BuildContext context) {
    EventBus.doOpenRoom(room.identifier, clientId: room.client.identifier);

    Navigator.of(context).pop();
  }
}

/// Vommet issue 474: an app action in the quick switcher, e.g. switching
/// redacted mode on or off.
class QuickSwitcherSearchItemAction implements QuickSwitcherSearchItem {
  QuickSwitcherSearchItemAction(
      {required this.label,
      required this.id,
      required this.icon,
      required this.action,
      this.shortcut});

  final String label;
  final IconData icon;
  final String? shortcut;

  /// Runs while the switcher is still open, so it can show a message.
  final void Function(BuildContext context) action;

  @override
  String id;

  @override
  String get searchEntry => label;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: Icon(icon),
      title: Text(label),
      trailing: shortcut == null
          ? null
          : Text(shortcut!, style: Theme.of(context).textTheme.labelSmall),
      onTap: () => onTap(context),
    );
  }

  @override
  void onTap(BuildContext context) {
    action(context);
    Navigator.of(context).pop();
  }
}

List<QuickSwitcherSearchItem> redactedModeSwitcherActions() {
  if (!redactedModeAvailable) return const [];
  final on = preferences.redactionActive;
  return [
    QuickSwitcherSearchItemAction(
      label: on ? redactedModeTurnOff : redactedModeTurnOn,
      id: "redacted-mode",
      icon: on ? Icons.visibility : Icons.visibility_off,
      shortcut: redactedModeShortcutLabel,
      action: (context) => setRedactedMode(context, !on),
    ),
    QuickSwitcherSearchItemAction(
      label: redactedModeSettings,
      id: "redacted-mode-settings",
      icon: Icons.settings,
      action: (context) {
        final navigatorContext = Navigator.of(context).context;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (navigatorContext.mounted) {
            openRedactedModeSettings(navigatorContext);
          }
        });
      },
    ),
  ];
}

/// Vommet issue 475: a room in the quick switcher, following redacted mode.
Widget quickSwitcherRoomPanel(BuildContext context, Room room,
    {required VoidCallback onTap}) {
  final redaction = RedactionScope.of(context);
  final senderId = room.lastMessage?.senderId;
  final sender = senderId == null ? null : room.getMemberOrFallback(senderId);
  return RoomPanelView(
    displayName: redaction.roomDisplayName(room),
    color: room.defaultColor,
    onTap: onTap,
    avatar: room.avatar,
    recentEventSender:
        sender == null ? null : redaction.name(sender.displayName, senderId!),
    recentEventSenderColor: sender == null
        ? null
        : redaction.nameColor(sender.defaultColor, senderId!),
    body: room.lastMessage == null
        ? null
        : redaction.text(room.lastMessage!.plainTextBody),
  );
}

class _QuickSwitcherState extends State<QuickSwitcher> {
  List<QuickSwitcherSearchItem> items = List.empty(growable: true);

  List<QuickSwitcherSearchItem> searchResults = List.empty();

  @override
  void initState() {
    items.addAll(redactedModeSwitcherActions());

    for (var client in clientManager!.clients) {
      var dm = client.getComponent<DirectMessagesComponent>();

      for (var room in client.rooms) {
        // Vommet: an upgraded room shows as its replacement only.
        if (isSupersededRoom(room)) continue;
        // Vommet issue 99: and a person once, as their newest room.
        if (dm?.isOlderDirectMessage(room) == true) continue;
        if (dm?.isRoomDirectMessage(room) == true) {
          var partner = dm!.getDirectMessagePartnerId(room);
          items.add(QuickSwitcherSearchItemRoom(room,
              id: partner ?? room.identifier));
        } else {
          items.add(QuickSwitcherSearchItemRoom(room, id: room.identifier));
        }
      }
    }

    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 500,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            decoration: InputDecoration(icon: Icon(Icons.search)),
            maxLines: 1,
            onChanged: doSearch,
            onSubmitted: (value) {
              searchResults.firstOrNull?.onTap(context);
            },
            autofocus: true,
          ),
          if (searchResults.isEmpty) buildDefaultView(),
          if (searchResults.isNotEmpty)
            tiamat.Panel(
              mode: TileType.surfaceContainerLow,
              header: "Search Results",
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
                child: Column(
                  children: [
                    for (var result in searchResults) result.build(context),
                  ],
                ),
              ),
            )
        ],
      ),
    );
  }

  Column buildDefaultView() {
    return Column(
      children: [
        tiamat.Panel(
          mode: TileType.surfaceContainerLow,
          header: "Direct Messages",
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              spacing: 8,
              children: [
                for (var room in clientManager!
                    .directMessages.directMessageRooms
                    .sorted((a, b) =>
                        b.lastEventTimestamp.compareTo(a.lastEventTimestamp)))
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      mouseCursor: WidgetStateMouseCursor.clickable,
                      onTap: () {
                        EventBus.doOpenRoom(room.identifier,
                            clientId: room.client.identifier);

                        Navigator.of(context).pop();
                      },
                      child: tiamat.Avatar(
                          image: room.avatar,
                          placeholderColor: room.defaultColor,
                          placeholderText: room.displayName,
                          redactionKey:
                              RedactionScope.of(context).roomAvatarKey(room)),
                    ),
                  )
              ],
            ),
          ),
        ),
        tiamat.Panel(
            mode: TileType.surfaceContainerLow,
            header: "Recent Activity",
            child: Column(
              spacing: 0,
              children: [
                for (var room in clientManager!.rooms
                    .where((r) => !isSupersededRoom(r))
                    .sorted((a, b) =>
                        b.lastEventTimestamp.compareTo(a.lastEventTimestamp))
                    .take(4))
                  quickSwitcherRoomPanel(context, room, onTap: () {
                    EventBus.doOpenRoom(room.identifier,
                        clientId: room.client.identifier);

                    Navigator.of(context).pop();
                  })
              ],
            ))
      ],
    );
  }

  void doSearch(String text) {
    if (text.isEmpty) {
      setState(() {
        searchResults = List.empty();
      });
      return;
    }

    var searchItems = items;
    var searchText = text;

    if (text.startsWith("@")) {
      searchItems = items.where((i) => i.id.startsWith("@")).toList();
    }

    // Vommet: ranked like New Home's search (vommet_quick_switcher_rank.dart).
    var results = rankQuickSwitcher(searchItems, searchText);
    setState(() {
      searchResults = results;
    });
  }
}
