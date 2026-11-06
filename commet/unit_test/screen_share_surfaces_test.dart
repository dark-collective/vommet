import 'package:commet/client/components/room_call/room_call_component.dart';
import 'package:commet/ui/molecules/room_call_bar.dart';
import 'package:commet/ui/organisms/unified_chat_list/unified_chat_list_preference.dart';
// Production widgets with fixture call state. No Matrix or media connection.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:commet/client/client.dart';
import 'package:commet/client/components/component.dart';
import 'package:commet/client/components/room_component.dart';
import 'package:commet/client/components/activities/activities_component.dart';
import 'package:commet/client/components/voip/screen_share_status.dart';
import 'package:commet/client/components/voip_room/voip_room_component.dart';
import 'package:commet/client/components/voip/voip_session.dart';
import 'package:commet/client/member.dart';
import 'package:commet/client/permissions.dart';
import 'package:commet/config/layout_style.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/atoms/room_text_button.dart';
import 'package:commet/client/components/profile/profile_component.dart';
import 'package:commet/ui/organisms/unified_chat_list/unified_chat_model.dart';
import 'package:commet/ui/organisms/unified_chat_list/unified_chat_rows.dart';
import 'package:commet/ui/organisms/voip_room_view/voip_room_view.dart';
import 'package:commet/utils/image_or_icon.dart';
import 'package:commet/utils/notifying_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_dark.dart';
import 'package:tiamat/config/style/theme_light.dart';
import 'package:tiamat/config/style/theme_amoled.dart';

class _Client extends Fake implements Client {
  @override
  String get identifier => 'fixture';
  @override
  Profile? get self => null;
  @override
  T? getComponent<T extends Component>() => null;
  // The shared unread index listens to these; the fixture never syncs.
  @override
  NotifyingList<Room> get rooms => NotifyingList<Room>.empty(growable: true);
  @override
  Stream<void> get onSync => const Stream.empty();
  @override
  Stream<Room> get onRoomAdded => const Stream.empty();
  @override
  Stream<Room> get onRoomRemoved => const Stream.empty();
}

class _Member extends Fake implements Member {
  _Member(this.identifier, this.displayName, this.defaultColor);
  @override
  final String identifier;
  @override
  final String displayName;
  @override
  final Color defaultColor;
  @override
  ImageProvider? get avatar => null;
  @override
  ImageProvider? get largeAvatar => null;
}

class _Permissions extends Permissions {}

final _people = [
  _Member('@alex:example.org', 'Alex Rivera', Colors.blue),
  _Member('@morgan:example.org', 'Morgan Chen', Colors.purple),
  _Member('@jamie:example.org', 'Jamie', Colors.teal),
];

class _Call extends Fake
    implements VoipRoomComponent, ScreenShareStatus, RoomCallComponent {
  _Call(this.room);
  @override
  final Room room;
  @override
  Client get client => room.client;
  @override
  Map<String, int> get screenShares => {
        for (final p in _people.take(2))
          p.identifier: DateTime.now().millisecondsSinceEpoch + 3600000
      };
  @override
  Stream<void> get onScreenSharesChanged => const Stream.empty();
  @override
  List<String> getCurrentParticipants() =>
      _people.map((p) => p.identifier).toList();
  @override
  Stream<void> get onParticipantsChanged => const Stream.empty();
  @override
  VoipSession? get currentSession => null;
  @override
  DateTime? get callStartedAt => null;
  @override
  bool get canJoinCall => true;
  @override
  Future<String?> getCallServerUrl() async => 'fixture.invalid';
}

class _Activities extends Fake implements ActivitiesComponent {
  @override
  List<RoomActivitySession> getSessions() => [
        RoomActivitySession(
            participants: _people.map((p) => p.identifier).toSet(),
            application: 'm.call',
            thirdparty: false,
            icon: ImageOrIcon(icon: Icons.call))
      ];
  @override
  Stream<void> get onSessionsChanged => const Stream.empty();
}

class _Room extends Fake implements Room {
  late final call = _Call(this);
  final activities = _Activities();
  @override
  final Client client = _Client();
  @override
  String get identifier => '!fixture:example.org';
  @override
  String get localId => 'fixture:!fixture:example.org';
  @override
  String get displayName => 'Game night';
  @override
  Color get defaultColor => Colors.indigo;
  @override
  ImageProvider? get avatar => null;
  @override
  IconData get icon => Icons.headphones;
  @override
  bool get isSpecialRoomType => true;
  @override
  bool get isE2EE => false;
  @override
  bool get isFavorite => false;
  @override
  bool get isBanned => false;
  @override
  bool get isRemoved => false;
  @override
  int get notificationCount => 0;
  @override
  int get highlightedNotificationCount => 0;
  @override
  int get badgeCount => 0;
  @override
  bool get messagesAreNoisy => false;
  @override
  PushRule get pushRule => PushRule.notify;
  @override
  Permissions get permissions => _Permissions();
  @override
  Stream<void> get onUpdate => const Stream.empty();
  @override
  Member getMemberOrFallback(String id) =>
      _people.firstWhere((p) => p.identifier == id);
  @override
  Future<Member> fetchMember(String id) async => getMemberOrFallback(id);
  @override
  T? getComponent<T extends RoomComponent>() {
    for (final component in [call, activities]) {
      if (component is T) return component;
    }
    return null;
  }
}

Future<void> _fonts() async {
  final flutter = Platform.environment['FLUTTER_ROOT'];
  for (final (family, path) in [
    ('RobotoCustom', 'assets/font/roboto/Roboto-Regular.ttf'),
    (
      'NunitoSans',
      'assets/font/nunito/NunitoSans-VariableFont_YTLC,opsz,wdth,wght.ttf'
    ),
    if (flutter != null)
      (
        'MaterialIcons',
        '$flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf'
      ),
  ]) {
    final loader = FontLoader(family)
      ..addFont(File(path).readAsBytes().then(ByteData.sublistView));
    await loader.load();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final output = Platform.environment['VOMMET_SCREEN_SHARE_CAPTURES'];
  setUpAll(() async {
    if (output != null) await _fonts();
  });
  for (final style in LayoutStyle.values) {
    for (final unified in (style == LayoutStyle.custom
        ? [false, true]
        : [style == LayoutStyle.telegram])) {
      for (final phone in [false, true]) {
        for (final roster in (phone ? [false, true] : [true])) {
          final name =
              '${style.name}${style == LayoutStyle.custom ? (unified ? '-unified' : '-split') : ''}-${phone ? 'phone' : 'desktop'}-${roster ? 'roster' : 'list'}';
          testWidgets(name, (tester) async {
            // ignore: invalid_use_of_visible_for_testing_member
            SharedPreferences.setMockInitialValues({});
            await preferences.init();
            await pickLayoutStyle(style);
            await experimentUnifiedChatList.set(unified);
            await ScreenShareStatus.experiment.set(true);
            final scale = style == LayoutStyle.custom ? 1.6 : 1.0;
            final size = phone ? const Size(393, 852) : const Size(1200, 800);
            tester.view.physicalSize = size;
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.reset);
            await preferences.layoutOverride.set(phone ? 'mobile' : 'desktop');
            final room = _Room();
            final key = GlobalKey();
            Widget list() => unified
                ? ChatRowTile(
                    ChatEntry(
                        key: room.localId,
                        roomId: room.identifier,
                        name: room.displayName,
                        kind: ChatKind.voice,
                        voiceCount: 3,
                        voiceNames: () =>
                            _people.map((p) => p.displayName).toList(),
                        source: room),
                    now: DateTime.now())
                : RoomTextButton(room);
            final theme = switch (style) {
              LayoutStyle.discord => ThemeDark.theme,
              LayoutStyle.telegram => ThemeLight.theme,
              LayoutStyle.custom => ThemeAmoled.theme,
            };
            await tester.pumpWidget(RepaintBoundary(
                key: key,
                child: MaterialApp(
                    debugShowCheckedModeBanner: false,
                    theme: theme,
                    home: MediaQuery(
                        data: MediaQueryData(
                            size: size, textScaler: TextScaler.linear(scale)),
                        child: Scaffold(
                            appBar: AppBar(
                                title: Text('Game night · ${style.name}')),
                            body: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Padding(
                                      padding: EdgeInsets.all(12),
                                      child: Text(
                                          'Integrated widgets · Fixture participants · No media connection',
                                          style: TextStyle(fontSize: 11))),
                                  Expanded(
                                      child: phone
                                          ? (roster
                                              ? VoipRoomView(room.call)
                                              : ListView(children: [list()]))
                                          : Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                  SizedBox(
                                                      width: 340,
                                                      child: ListView(
                                                          children: [list()])),
                                                  const VerticalDivider(
                                                      width: 1),
                                                  Expanded(
                                                      child: VoipRoomView(
                                                          room.call)),
                                                ])),
                                ]))))));
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 300));
            expect(tester.takeException(), isNull);
            expect(find.text('LIVE'), findsWidgets);
            if (output != null) {
              await tester.runAsync(() async {
                final render = key.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
                final im = await render.toImage(pixelRatio: 1);
                final bytes =
                    await im.toByteData(format: ui.ImageByteFormat.png);
                await Directory(output).create(recursive: true);
                await File('$output/$name.png')
                    .writeAsBytes(bytes!.buffer.asUint8List());
                im.dispose();
              });
            }
            await tester.pumpWidget(const SizedBox());
            await tester.pump();
          });
        }
      }
    }
  }
  testWidgets('ordinary room call avatars fit a phone with large text',
      (tester) async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    await ScreenShareStatus.experiment.set(true);
    await preferences.experimentRoomCalls.set(true);
    final room = _Room();
    final barKey = GlobalKey();
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
        theme: ThemeLight.theme,
        home: MediaQuery(
            data: const MediaQueryData(
                size: Size(393, 852), textScaler: TextScaler.linear(2)),
            child: Scaffold(
                body: Column(children: [
              const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text("Fixture call · 200% text")),
              RepaintBoundary(key: barKey, child: RoomCallBar(room)),
            ])))));
    await tester.pump();
    expect(find.text('LIVE'), findsOneWidget);
    expect(tester.takeException(), isNull);
    if (output != null) {
      await tester.runAsync(() async {
        final render =
            barKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await render.toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('$output/ordinary-call-bar-large-text.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    await tester.pumpWidget(const SizedBox());
  });
}
