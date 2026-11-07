import 'package:commet/config/preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _a = "@a:example.org";
const _b = "@b:example.org";

void main() {
  setUp(() {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
  });

  test("room thread filters default to all and are stored per room", () async {
    final preferences = Preferences();
    await preferences.init();

    expect(
      preferences.getRoomThreadListFilterMine(_a, "!one:example.org"),
      isFalse,
    );
    await preferences.setRoomThreadListFilterMine(_a, "!one:example.org", true);

    expect(preferences.getRoomThreadListFilterMine(_a, "!one:example.org"),
        isTrue);
    expect(
      preferences.getRoomThreadListFilterMine(_a, "!two:example.org"),
      isFalse,
    );
  });

  test("room thread filters survive preferences reinitialization", () async {
    final first = Preferences();
    await first.init();
    await first.setRoomThreadListFilterMine(_a, "!room:example.org", true);

    final restarted = Preferences();
    await restarted.init();

    expect(
        restarted.getRoomThreadListFilterMine(_a, "!room:example.org"), isTrue);
  });

  // Vommet issue 984.
  test("two accounts in one room keep their own filter", () async {
    final preferences = Preferences();
    await preferences.init();
    await preferences.setRoomThreadListFilterMine(
        _a, "!room:example.org", true);

    expect(preferences.getRoomThreadListFilterMine(_b, "!room:example.org"),
        isFalse);
    expect(preferences.getRoomThreadListFilterMine(_a, "!room:example.org"),
        isTrue);
  });

  test("choosing all removes the stored key", () async {
    final preferences = Preferences();
    await preferences.init();
    await preferences.setRoomThreadListFilterMine(
        _a, "!room:example.org", true);
    await preferences.setRoomThreadListFilterMine(
        _a, "!room:example.org", false);

    final stored = await SharedPreferences.getInstance();
    expect(stored.getKeys().where((k) => k.contains("thread_list_filter")),
        isEmpty);
    expect(preferences.getRoomThreadListFilterMine(_a, "!room:example.org"),
        isFalse);
  });

  test("an older room-only choice is read until the next choice", () async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues(
        {"room_thread_list_filter_mine.!room:example.org": true});
    final preferences = Preferences();
    await preferences.init();

    expect(preferences.getRoomThreadListFilterMine(_a, "!room:example.org"),
        isTrue);
    await preferences.setRoomThreadListFilterMine(
        _a, "!room:example.org", false);
    expect(preferences.getRoomThreadListFilterMine(_a, "!room:example.org"),
        isFalse);
  });
}
