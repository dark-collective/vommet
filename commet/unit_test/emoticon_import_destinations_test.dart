import 'package:commet/client/client.dart';
import 'package:commet/client/components/emoticon/emoji_pack.dart';
import 'package:commet/client/components/emoticon/emoticon_component.dart';
import 'package:commet/client/matrix/components/emoticon/matrix_emoticon_component.dart';
import 'package:commet/ui/pages/settings/categories/room/emoji_packs/import_destinations.dart';
import 'package:flutter_test/flutter_test.dart';

class _Pack extends Fake implements EmoticonPack {
  _Pack(this.displayName);
  @override
  final String displayName;
}

class _Room extends Fake implements Room {
  _Room(this.displayName);
  @override
  final String displayName;
}

class _Account extends Fake implements EmoticonComponent {
  _Account(this.ownedPacks);
  @override
  final List<EmoticonPack> ownedPacks;
  @override
  bool get canCreatePack => true;
}

class _RoomPacks extends Fake implements RoomEmoticonComponent {
  _RoomPacks(String name, this.ownedPacks, {this.canCreatePack = true})
      : room = _Room(name);
  @override
  final Room room;
  @override
  final List<EmoticonPack> ownedPacks;
  @override
  bool get isStickerRoom => true;
  @override
  final bool canCreatePack;
}

void main() {
  final stickerRoom = _RoomPacks("Sticker packs", [_Pack("Grumpy Toads")]);
  final friendsRoom = _RoomPacks("Juniper's stickers", [_Pack("Cozy Ducks")],
      canCreatePack: false);

  List<String> labels(_Account account, {required bool usePersonalPack}) =>
      EmoticonImportDestinations.buildFrom(
        origin: account,
        account: account,
        stickerRooms: [stickerRoom, friendsRoom],
        roomComponent: null,
        usePersonalPack: usePersonalPack,
      ).map((d) => d.label).toList();

  test("switch off, no personal pack: no personal choices", () {
    expect(labels(_Account([]), usePersonalPack: false), [
      'New pack in sticker room "Sticker packs"',
      "New pack in a new sticker room",
      "Add to Grumpy Toads (Sticker packs)",
    ]);
  });

  test("switch off, existing personal pack: still not offered", () {
    final result =
        labels(_Account([_Pack("Space Otters")]), usePersonalPack: false);
    expect(result, isNot(contains("New personal pack")));
    expect(result, isNot(contains("Add to Space Otters (personal)")));
  });

  test("switch on, no personal pack: New personal pack comes back, first", () {
    final result = labels(_Account([]), usePersonalPack: true);
    expect(result.first, "New personal pack");
  });

  test("switch on, existing personal pack: add to it, no second one", () {
    final result =
        labels(_Account([_Pack("Space Otters")]), usePersonalPack: true);
    expect(result, isNot(contains("New personal pack")));
    expect(result, contains("Add to Space Otters (personal)"));
  });

  test("rooms you can't edit are never a destination", () {
    final result = labels(_Account([]), usePersonalPack: true);
    expect(result.where((l) => l.contains("Juniper")), isEmpty);
    expect(result.where((l) => l.contains("Cozy Ducks")), isEmpty);
  });

  test("multi-link import: each link a new pack, sticker room first", () {
    final all = EmoticonImportDestinations.buildFrom(
      origin: _Account([]),
      account: _Account([]),
      stickerRooms: [stickerRoom],
      roomComponent: null,
      usePersonalPack: true,
    );
    expect(
        EmoticonImportDestinations.forMultiImport(all)
            .map((d) => d.label)
            .toList(),
        [
          'Each as a new pack in sticker room "Sticker packs"',
          "Each as a new pack in a new sticker room",
        ]);
  });

  test("multi-link import without sticker rooms: a new one by default", () {
    final account = _Account([]);
    final all = EmoticonImportDestinations.buildFrom(
      origin: account,
      account: account,
      stickerRooms: [],
      roomComponent: null,
      usePersonalPack: false,
    );
    final multi = EmoticonImportDestinations.forMultiImport(all);
    expect(multi.first.kind, EmoticonImportKind.newStickerRoom);
  });

  test("new account packs go to account data only with the switch on", () {
    expect(
        MatrixEmoticonComponent.writesToPersonalPack(
            usePersonalPack: false, hasPersonalPack: false),
        isFalse);
    expect(
        MatrixEmoticonComponent.writesToPersonalPack(
            usePersonalPack: true, hasPersonalPack: false),
        isTrue);
    expect(
        MatrixEmoticonComponent.writesToPersonalPack(
            usePersonalPack: true, hasPersonalPack: true),
        isFalse);
  });
}
