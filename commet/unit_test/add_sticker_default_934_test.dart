import 'package:commet/client/client.dart';
import 'package:commet/client/components/component.dart';
import 'package:commet/client/components/emoticon/emoji_pack.dart';
import 'package:commet/client/components/emoticon/emoticon_component.dart';
import 'package:commet/client/components/room_component.dart';
import 'package:commet/client/timeline_events/timeline_event_sticker.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/molecules/sticker_pack_sheet.dart';
import 'package:commet/ui/pages/settings/categories/room/emoji_packs/import_destinations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

// Vommet issue 934: "Add sticker to…" opened from a chat preselected "New
// pack in <this chat>", so one tap on Add wrote a one-sticker pack into the
// DM (where it shows in both people's Library). Your own sticker room (or a
// new one) is now the default; the chat stays in the list.

typedef _D = EmoticonImportDestinations;

class _Client extends Fake implements Client {
  EmoticonComponent? account;
  @override
  T? getComponent<T extends Component>() =>
      T == EmoticonComponent ? account as T? : null;
}

class _Room extends Fake implements Room {
  _Room(this.displayName, this.client);
  @override
  final String displayName;
  @override
  final Client client;
  RoomEmoticonComponent? packs;
  @override
  T? getComponent<T extends RoomComponent>() =>
      T == RoomEmoticonComponent ? packs as T? : null;
}

class _Account extends Fake implements EmoticonComponent {
  _Account(this.client, this.stickerRoomComponents);
  @override
  final Client client;
  @override
  final List<EmoticonComponent> stickerRoomComponents;
  @override
  List<EmoticonPack> get ownedPacks => const [];
  @override
  bool get canCreatePack => true;
}

class _RoomPacks extends Fake implements RoomEmoticonComponent {
  _RoomPacks(this.room, {this.isStickerRoom = false})
      : isOwnStickerRoom = isStickerRoom;
  @override
  final Room room;
  @override
  final bool isStickerRoom;
  @override
  final bool isOwnStickerRoom;
  @override
  List<EmoticonPack> get ownedPacks => const [];
  @override
  bool get canCreatePack => true;
}

class _Sticker extends Fake implements TimelineEventSticker {
  @override
  String get stickerName => "grumpy toad";
}

/// Opens the real "Add sticker to…" dialog (no pack found, as in the
/// report) from a chat named [chat], with or without your own sticker room.
/// The app sits in a RepaintBoundary keyed `r934` for renders.
Future<void> pumpAddSticker(WidgetTester tester,
    {required String chat,
    required bool hasStickerRoom,
    Size size = const Size(1280, 800),
    bool mobile = false}) async {
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({});
  await preferences.init();
  await preferences.layoutOverride.set(mobile ? "mobile" : "desktop");

  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final client = _Client();
  final stickerRoom = _Room("Sticker packs", client);
  stickerRoom.packs = _RoomPacks(stickerRoom, isStickerRoom: true);
  client.account = _Account(client, [if (hasStickerRoom) stickerRoom.packs!]);
  final room = _Room(chat, client);
  room.packs = _RoomPacks(room);

  await tester.pumpWidget(RepaintBoundary(
    key: const ValueKey('r934'),
    child: MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => AddStickersDialog.show(context,
                room: room, event: _Sticker(), pack: null),
            child: const Text("open"),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text("open"));
  await tester.pumpAndSettle();
}

typedef _Selector = tiamat.DropdownSelector<EmoticonImportDestination>;

_Selector destinationSelector(WidgetTester tester) =>
    tester.widget(find.byWidgetPredicate((w) => w is _Selector));

void main() {
  final inStickerRoom = _D.labelImportNewPackInStickerRoom("Sticker packs");
  final newStickerRoom = EmoticonImportDestinations.labelImportNewStickerRoom;

  for (final chat in ["Juniper", "Pond Club"]) {
    testWidgets("$chat: your sticker room first", (tester) async {
      await pumpAddSticker(tester, chat: chat, hasStickerRoom: true);
      final selector = destinationSelector(tester);
      expect(selector.value.label, inStickerRoom);
      expect(find.text(inStickerRoom), findsOneWidget);
      // The chat stays offered, just not first.
      final here = EmoticonImportDestinations.labelImportNewPackIn(chat);
      expect(selector.items.map((d) => d.label), contains(here));
      expect(selector.items.first.label, isNot(here));
    });

    testWidgets("$chat: no sticker room: a new one first", (tester) async {
      await pumpAddSticker(tester, chat: chat, hasStickerRoom: false);
      final selector = destinationSelector(tester);
      expect(selector.value.label, newStickerRoom);
      expect(find.text(AddStickersDialog.labelStickerRoomName), findsOneWidget);
      expect(selector.items.map((d) => d.label),
          contains(EmoticonImportDestinations.labelImportNewPackIn(chat)));
    });
  }

  testWidgets("phone layout (bottom sheet): same default", (tester) async {
    const phone = Size(412, 915);
    await pumpAddSticker(tester,
        chat: "Juniper", hasStickerRoom: true, size: phone, mobile: true);
    expect(destinationSelector(tester).value.label, inStickerRoom);
  });
}
