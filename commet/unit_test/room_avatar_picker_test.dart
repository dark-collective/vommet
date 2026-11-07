import 'dart:convert';

import 'package:commet/client/matrix/components/profile/matrix_profile_component.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/pages/room_info/room_info_dialog.dart';
import 'package:commet/ui/pages/settings/categories/room/appearance/room_appearance_settings_view.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_dark.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

import 'roomlist_fixture.dart';

class _GalleryPicker extends ImagePickerPlatform {
  XFile? image;
  int calls = 0;

  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async {
    expect(source, ImageSource.gallery);
    calls++;
    return image;
  }
}

class _Room extends MatrixRoom {
  _Room(MatrixClient client, String id, this.picture)
      : super(client, client.getMatrixClient().getRoomById(id)!,
            client.getMatrixClient());

  ImageProvider? picture;
  final picked = <Uint8List>[];
  final topics = <String>[];
  int removals = 0;

  @override
  ImageProvider? get avatar => picture;

  @override
  Future<void> setRoomAvatar(Uint8List bytes, String? mimeType) async {
    picture = MemoryImage(bytes);
    picked.add(bytes);
  }

  @override
  Future<void> removeRoomAvatar() async {
    picture = null;
    removals++;
  }

  @override
  Future<void> setTopic(String topic) async {
    topics.add(topic);
  }
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<(_Room, _GalleryPicker, Uint8List)> _openEditor(
    WidgetTester tester) async {
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({});
  await preferences.init();
  final bytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==');
  expect(defaultTargetPlatform, TargetPlatform.iOS);
  final originalPicker = ImagePickerPlatform.instance;
  final picker = _GalleryPicker();
  ImagePickerPlatform.instance = picker;
  addTearDown(() {
    ImagePickerPlatform.instance = originalPicker;
  });
  tester.view.physicalSize = const Size(1194, 834);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final client = await tester.runAsync(() async {
    final client = await signedInClient('avatar-picker');
    client.self = MatrixProfile(client, matrix.Profile(userId: me));
    await sync(client, join: {
      '!test:example.com': matrix.JoinedRoomUpdate(state: [
        ...roomState('!test:example.com', name: 'Test room'),
        stateEvent('m.room.power_levels', {
          'users': {me: 100},
        }),
      ]),
    });
    return client;
  });
  final room = _Room(client!, '!test:example.com', MemoryImage(bytes));
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester
        .runAsync(() => client.getMatrixClient().dispose(closeDatabase: true));
  });
  await tester.pumpWidget(MaterialApp(
    theme: ThemeDark.theme,
    home: Builder(
      builder: (context) => TextButton(
        onPressed: () => showRoomInfoDialog(context, room),
        child: const Text('Room info'),
      ),
    ),
  ));

  await _tap(tester, find.text('Room info'));
  expect(find.byType(RoomInfoDialog), findsOneWidget);
  await _tap(tester, find.byTooltip('Edit room profile'));
  expect(find.byType(RoomAppearanceSettingsView), findsOneWidget);
  return (room, picker, bytes);
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('FlutterWebRTC.Event'), (_) async => null);
  });
  tearDownAll(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('FlutterWebRTC.Event'), null);
  });
  testWidgets('iPad Room info avatar actions return to the editor',
      (tester) async {
    final (room, picker, bytes) = await _openEditor(tester);
    final avatarButton = find.byType(tiamat.ImageButton);
    await _tap(tester, avatarButton);
    await _tap(tester, find.text('Pick image'));
    expect(picker.calls, 1);
    expect(find.text('Pick image'), findsNothing);
    expect(avatarButton, findsOneWidget);
    expect(room.picked, isEmpty);

    await tester.runAsync(
        () => precacheImage(MemoryImage(bytes), tester.element(avatarButton)));
    picker.image = XFile.fromData(bytes, path: '/avatar.png');
    await _tap(tester, avatarButton);
    await _tap(tester, find.text('Pick image'));
    await _tap(tester, find.text('Use without cropping'));
    expect(room.picked, [bytes]);
    expect(avatarButton, findsOneWidget);
    picker.image = null;

    await _tap(tester, avatarButton);
    await _tap(tester, find.text('Cancel'));
    expect(picker.calls, 2);
    expect(room.removals, 0);

    await _tap(tester, avatarButton);
    await _tap(tester, find.text('Remove image'));
    await _tap(tester, find.text('Cancel').hitTestable());
    expect(room.removals, 0);
    expect(find.text('Pick image'), findsOneWidget);

    await _tap(tester, find.text('Remove image'));
    await _tap(tester, find.text('Remove'));
    expect(room.removals, 1);
    expect(find.text('Pick image'), findsNothing);

    await _tap(tester, avatarButton);
    expect(picker.calls, 3);
    expect(find.text('Pick image'), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('iPad Room info Set topic returns through the popup navigator',
      (tester) async {
    final (room, _, _) = await _openEditor(tester);
    await _tap(tester, find.text('Set a topic'));
    expect(find.text('Set Topic'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Updated topic');
    await _tap(tester, find.text('Submit'));
    expect(room.topics, ['Updated topic']);
    expect(find.text('Updated topic'), findsOneWidget);
    expect(find.byType(RoomAppearanceSettingsView), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
}
