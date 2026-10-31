import 'package:commet/config/preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
  });

  test("room thread filters default to all and are stored per room", () async {
    final preferences = Preferences();
    await preferences.init();

    expect(
      preferences.getRoomThreadListFilterMine("!one:example.org"),
      isFalse,
    );
    await preferences.setRoomThreadListFilterMine("!one:example.org", true);

    expect(preferences.getRoomThreadListFilterMine("!one:example.org"), isTrue);
    expect(
      preferences.getRoomThreadListFilterMine("!two:example.org"),
      isFalse,
    );
  });

  test("room thread filters survive preferences reinitialization", () async {
    final first = Preferences();
    await first.init();
    await first.setRoomThreadListFilterMine("!room:example.org", true);

    final restarted = Preferences();
    await restarted.init();

    expect(restarted.getRoomThreadListFilterMine("!room:example.org"), isTrue);
  });
}
