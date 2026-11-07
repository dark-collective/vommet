// Vommet issue 1140: drive the real member list from pinned to inline and
// inspect its painted notice, including the surrounding gradient panel.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:commet/client/client.dart';
import 'package:commet/client/components/component.dart';
import 'package:commet/client/components/profile/profile_component.dart';
import 'package:commet/client/components/room_component.dart';
import 'package:commet/client/components/user_presence/user_presence_component.dart';
import 'package:commet/client/member.dart';
import 'package:commet/client/permissions.dart';
import 'package:commet/client/role.dart';
import 'package:commet/config/layout_style.dart';
import 'package:commet/config/room_layout_options.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/molecules/user_list.dart';
import 'package:commet/ui/organisms/new_home/new_home_cards.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/atoms/foundation.dart';
import 'package:tiamat/atoms/tile.dart';
import 'package:tiamat/config/style/theme_amoled.dart';
import 'package:tiamat/config/style/theme_dark.dart';
import 'package:tiamat/config/style/theme_gradient.dart';
import 'package:tiamat/config/style/theme_light.dart';

class _Permissions extends Permissions {
  _Permissions({this.canBan = false});
  @override
  final bool canBan;
}

class _Presence extends Fake implements UserPresenceComponent {
  _Presence({this.status = UserPresenceStatus.online});
  final UserPresenceStatus status;
  @override
  Stream<(String, UserPresence)> get onPresenceChanged => const Stream.empty();
  @override
  UserPresence? cachedPresence(String userId) => UserPresence(status);
  @override
  Future<UserPresence> getUserPresence(String userId) async =>
      UserPresence(status);
}

class _Self extends Fake implements Profile {
  @override
  String get identifier => "@me:lantern.example";
}

class _Client extends Fake implements Client {
  _Client(this.presence);
  final _Presence? presence;
  @override
  T? getComponent<T extends Component>() =>
      presence is T ? presence as T : null;
  @override
  Profile? get self => _Self();
}

class _FindMember implements Member {
  _FindMember(this.identifier, this.displayName);
  @override
  final String identifier;
  @override
  final String displayName;
  @override
  String get userName => identifier;
  @override
  String? get detail => null;
  @override
  String? get avatarId => null;
  @override
  ImageProvider? get avatar => null;
  @override
  ImageProvider? get largeAvatar => null;
  @override
  Color get defaultColor => Colors.teal;
}

class _Room extends Fake implements Room {
  _Room({this.members = const [], _Presence? presence, bool canBan = false})
      : client = _Client(presence),
        permissions = _Permissions(canBan: canBan);
  final List<Member> members;
  @override
  final Client client;
  @override
  final Permissions permissions;
  @override
  List<Member> membersList() => [...members];
  @override
  List<(Member, Role)> importantMembers() => [];
  @override
  List<Member> membersWithMembership(MemberMembership membership) => [];
  @override
  bool get isMembersListComplete => true;
  @override
  int get memberCount => members.length;
  @override
  bool memberHasLeft(String identifier) => false;
  @override
  Stream<void> get onMembersChanged => const Stream.empty();
  @override
  T? getComponent<T extends RoomComponent>() => null;
}

const _capture = ValueKey('1140-capture');
final _themes = [
  ('retro-storm', ThemeGradient.theme(ThemeGradient.byId('retro-storm')!)),
  ('dark', ThemeDark.theme),
  ('light', ThemeLight.theme),
  ('amoled', ThemeAmoled.theme),
];

Future<ScrollController> _pumpNotice(
    WidgetTester tester, ThemeData theme, Size size, LayoutStyle style) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  await pickLayoutStyle(style);
  await memberListOnlineSections.set(true);
  await memberListHideOffline.set(false);
  final controller = ScrollController();
  final room = _Room(
      members: List.generate(
          40, (i) => _FindMember('@member$i:example.org', 'Member $i')),
      presence: _Presence(status: UserPresenceStatus.unknown));
  await tester.pumpWidget(MaterialApp(
    theme: theme,
    home: RepaintBoundary(
      key: _capture,
      child: Foundation(
        child: Align(
          alignment: Alignment.centerRight,
          child: SizedBox(
            width: size.width < 600 ? size.width : 300,
            child: Tile(
              mode: size.width < 600
                  ? TileType.surface
                  : TileType.surfaceContainer,
              child: Material(
                color: Colors.transparent,
                child: RoomMemberList(
                  room,
                  directMessage: false,
                  controller: controller,
                  leading: const [
                    SliverToBoxAdapter(
                        child: SizedBox(
                            height: 50,
                            child: Center(child: Text('Room members')))),
                  ],
                  listPadding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return controller;
}

Future<void> _scrollInline(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
    await tester.pumpAndSettle();
    if (find
        .ancestor(of: _notice, matching: find.byType(Positioned))
        .evaluate()
        .isEmpty) {
      return;
    }
  }
  fail('The real notice did not reach its inline position');
}

Future<(ui.Image, ByteData)> _pixels(WidgetTester tester) async {
  final boundary =
      tester.renderObject<RenderRepaintBoundary>(find.byKey(_capture));
  return (await tester.runAsync(() async {
    final image = await boundary.toImage();
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    return (image, bytes);
  }))!;
}

Color _pixel(ui.Image image, ByteData bytes, Offset point) {
  final i = (point.dy.floor() * image.width + point.dx.floor()) * 4;
  return Color.fromARGB(bytes.getUint8(i + 3), bytes.getUint8(i),
      bytes.getUint8(i + 1), bytes.getUint8(i + 2));
}

Finder get _notice => find.ancestor(
    of: find.textContaining('40 offline or unknown').hitTestable(),
    matching: find.byType(DashedOutline));

Future<List<int>> _noticePaint(WidgetTester tester) async {
  expect(_notice, findsOneWidget);
  final rect = tester.getRect(_notice);
  final (image, bytes) = await _pixels(tester);
  try {
    // The notice's corner and outer margins expose the actual panel, not an
    // opaque square swatch. Nearby samples at the same y allow a gradient.
    for (final y in [rect.top - 4, rect.top + 1, rect.bottom + 4]) {
      final corner = _pixel(image, bytes, Offset(rect.left + 1, y));
      final panel = _pixel(image, bytes, Offset(rect.left - 2, y));
      for (final (x, y) in [
        (corner.r, panel.r),
        (corner.g, panel.g),
        (corner.b, panel.b)
      ]) {
        expect((x - y).abs(), lessThan(3 / 255),
            reason:
                'No square backdrop or scrolling text in the notice margins');
      }
    }
    expect(tester.takeException(), isNull);
    // Sample the real painted fill, away from text, icon, outline and ripple.
    // Pinned and inline sit at the same screen coordinates in this long list,
    // so they must show the same gradient pixels as well as the same shape.
    return [
      for (final x in [rect.left + 20, rect.center.dx, rect.right - 20])
        _pixel(image, bytes, Offset(x, rect.bottom - 5)).toARGB32(),
    ];
  } finally {
    image.dispose();
  }
}

void main() {
  setUpAll(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
  });

  for (final style in LayoutStyle.values) {
    testWidgets(
        'Vommet issue 1140: $style keeps the notice painted consistently',
        (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final (name, theme) in _themes) {
        for (final size in [const Size(390, 844), const Size(1280, 800)]) {
          var controller = await _pumpNotice(tester, theme, size, style);
          try {
            expect(
                find.ancestor(of: _notice, matching: find.byType(Positioned)),
                findsOneWidget,
                reason: '$name $size pins on open');
            final pinnedPaint = await _noticePaint(tester);
            controller.jumpTo(137);
            await tester.pumpAndSettle();
            expect(await _noticePaint(tester), pinnedPaint,
                reason:
                    'Scrolling members cannot paint through the pinned notice');
            await _scrollInline(tester);
            expect(
                find.ancestor(of: _notice, matching: find.byType(Positioned)),
                findsNothing,
                reason: '$name $size reaches the inline row');
            expect(await _noticePaint(tester), pinnedPaint,
                reason: 'Pinned and inline show the same actual theme surface');
            await tester.tap(find.text('Hide').hitTestable());
            await tester.pumpAndSettle();
            expect(find.text('40 offline or unknown hidden').hitTestable(),
                findsOneWidget);
            expect(find.text('Member 39'), findsNothing);
            await _noticePaint(tester);
            await tester.tap(find.text('Show').hitTestable());
            await tester.pumpAndSettle();
            expect(find.text('40 offline or unknown').hitTestable(),
                findsOneWidget);
            // Reopening restores the pinned state without restoring a square.
            await tester.pumpWidget(const SizedBox());
            controller.dispose();
            controller = await _pumpNotice(tester, theme, size, style);
            expect(await _noticePaint(tester), pinnedPaint);
          } finally {
            await tester.pumpWidget(const SizedBox());
            controller.dispose();
          }
        }
      }
    });
  }
}
