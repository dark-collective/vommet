import 'package:commet/utils/dm_groups.dart';
import 'package:flutter_test/flutter_test.dart';

// Vommet issue 99: one row per person when you have several direct message
// rooms with them.
class _Dm {
  _Dm(this.id, this.partner, this.at, {this.unread = 0, this.mentions = 0});
  final String id;
  final String? partner;
  final DateTime at;
  final int unread;
  final int mentions;
}

Map<String, List<_Dm>> _group(List<_Dm> rooms) => DmGroups.byPartner(rooms,
    partnerOf: (r) => r.partner, lastActivity: (r) => r.at, idOf: (r) => r.id);

void main() {
  final old = _Dm("!old", "@mira:x", DateTime(2024, 1, 5), unread: 1);
  final newer =
      _Dm("!new", "@mira:x", DateTime(2026, 3, 2), unread: 2, mentions: 1);
  final theo = _Dm("!theo", "@theo:x", DateTime(2026, 3, 1));
  final noPartner = _Dm("!group", null, DateTime(2026, 3, 3));

  test("two rooms with one person: the newest is shown, the other is older",
      () {
    final groups = _group([old, theo, newer, noPartner]);
    expect(groups["@mira:x"], [newer, old]);
    expect(DmGroups.isOlder(old, groups["@mira:x"]), isTrue);
    expect(DmGroups.isOlder(newer, groups["@mira:x"]), isFalse);
  });

  test("a person with one room and rooms without a partner stay as they are",
      () {
    final groups = _group([old, theo, newer, noPartner]);
    expect(groups["@theo:x"], [theo]);
    expect(DmGroups.isOlder(theo, groups["@theo:x"]), isFalse);
    expect(groups.values.expand((g) => g), isNot(contains(noPartner)));
    expect(DmGroups.isOlder(noPartner, null), isFalse);
  });

  test("a new message in the older room makes it the shown one", () {
    final before = DmGroups.shownOfShared(_group([old, newer]));
    final revived = _Dm("!old", "@mira:x", DateTime(2026, 4, 1));
    final after = DmGroups.shownOfShared(_group([revived, newer]));
    expect(before["@mira:x"], newer);
    expect(after["@mira:x"], revived);
  });

  test("same activity time: the pick doesn't depend on list order", () {
    final a = _Dm("!a", "@jun:x", DateTime(2026, 1, 1));
    final b = _Dm("!b", "@jun:x", DateTime(2026, 1, 1));
    expect(_group([a, b])["@jun:x"]!.first, a);
    expect(_group([b, a])["@jun:x"]!.first, a);
  });

  test("the row's counts add up across the person's rooms", () {
    final counts = DmGroups.addCounts([newer, old],
        notifications: (r) => r.unread, highlights: (r) => r.mentions);
    expect(counts.notifications, 3);
    expect(counts.highlights, 1);
  });

  test("only people with several rooms are in shownOfShared", () {
    final shown = DmGroups.shownOfShared(_group([old, newer, theo]));
    expect(shown.keys, ["@mira:x"]);
  });
}
