import 'package:commet/config/room_row_size.dart';
import 'package:commet/main.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
  });

  test("rows are Standard until changed", () {
    expect(roomRowSize, RoomRowSize.standard);
    expect(RoomRowSize.parse("nonsense"), RoomRowSize.standard);
  });

  test("Standard keeps today's sizes", () {
    const s = RoomRowSize.standard;
    expect(s.sidebarRowHeight, 37);
    expect(s.sidebarAvatarRadius, 12);
    expect(s.panelAvatarRadius, 17);
    expect(s.shareAvatarRadius, 22);
    expect(s.rowGap, 0);
    final base = TextScaler.linear(1.3);
    expect(identical(s.textScaler(base), base), isTrue);
  });

  test("Large rows are bigger, with a gap", () async {
    await roomRowSizePreference.set(RoomRowSize.large.name);
    final l = roomRowSize;
    expect(l, RoomRowSize.large);
    const s = RoomRowSize.standard;
    expect(l.sidebarRowHeight, greaterThan(s.sidebarRowHeight));
    expect(l.panelAvatarRadius, greaterThan(s.panelAvatarRadius));
    expect(l.shareAvatarRadius, greaterThan(s.shareAvatarRadius));
    expect(l.rowGap, greaterThan(0));
    // The user's own text scaling is kept and enlarged.
    expect(l.textScaler(TextScaler.linear(1.2)).scale(10),
        closeTo(10 * 1.2 * l.textScale, 0.001));
  });
}
