import 'package:commet/ui/molecules/member_subtitle.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('server names up to 20 characters are kept whole', () {
    expect(shortServerName("nether.im"), "nether.im");
    expect(shortServerName("thursdaycouncil.org"), "thursdaycouncil.org");
    expect(shortServerName("a" * 20), "a" * 20);
  });

  test('longer names lose their start, cut at a dot or hyphen', () {
    expect(
        shortServerName("matrix.some-university.ac.uk"), "…university.ac.uk");
    expect(shortServerName("chat.example-community.org"), "…community.org");
  });

  test('a long name with no dot or hyphen near the end keeps its last 19', () {
    final name = "x.${"a" * 30}";
    expect(shortServerName(name), "…${"a" * 19}");
  });

  test('an unknown setting falls back to the homeserver, replaced by status',
      () {
    expect(MemberListSubtitle.parse("nonsense"),
        MemberListSubtitle.homeserverOrStatus);
    expect(MemberListSubtitle.parse("statusOff"), MemberListSubtitle.statusOff);
  });
}
