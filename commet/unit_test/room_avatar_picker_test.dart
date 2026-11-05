import 'dart:convert';
import 'dart:typed_data';

import 'package:commet/client/client.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/pages/settings/categories/room/appearance/room_appearance_settings_view.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_dark.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class _Client extends Fake implements Client {}

class _PickedFile extends PlatformFile {
  _PickedFile(Uint8List bytes)
      : super(name: 'avatar.png', size: bytes.length, bytes: bytes);

  @override
  XFile get xFile => XFile.fromData(bytes!, name: name);
}

class _FilePicker extends FilePicker {
  FilePickerResult? result;
  int calls = 0;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = false,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    calls++;
    return result;
  }
}

void main() {
  testWidgets('room avatar actions work inside the Room info navigator',
      (tester) async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    final bytes = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==');
    final picker = _FilePicker();
    FilePicker.platform = picker;
    final picked = <Uint8List>[];
    var removals = 0;

    final editor = Scaffold(
      body: RoomAppearanceSettingsView(
        avatar: MemoryImage(bytes),
        client: _Client(),
        displayName: 'Test room',
        identifier: '!test:example.org',
        color: Colors.teal,
        canEditAvatar: true,
        onImageRemoved: () async => removals++,
        onImagePicked: (image, _) => picked.add(image),
      ),
    );

    // Match Room info's root dialog and nested navigator for its subpages.
    Widget roomInfo(BuildContext context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => editor),
            ),
            child: const Text('Edit room profile'),
          ),
        );

    await tester.pumpWidget(MaterialApp(
      theme: ThemeDark.theme,
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => Dialog(
              child: Navigator(
                onGenerateRoute: (_) =>
                    MaterialPageRoute<void>(builder: roomInfo),
              ),
            ),
          ),
          child: const Text('Room info'),
        ),
      ),
    ));

    Future<void> tap(Finder finder) async {
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    final avatarButton = find.byType(tiamat.ImageButton);
    await tap(find.text('Room info'));
    await tap(find.text('Edit room profile'));
    await tap(avatarButton);
    await tap(find.text('Pick image'));
    expect(picker.calls, 1);
    expect(find.text('Pick image'), findsNothing);
    expect(avatarButton, findsOneWidget);
    expect(picked, isEmpty);

    await tester.runAsync(
        () => precacheImage(MemoryImage(bytes), tester.element(avatarButton)));
    picker.result = FilePickerResult([_PickedFile(bytes)]);
    await tap(avatarButton);
    await tap(find.text('Pick image'));
    await tap(find.text('Use without cropping'));
    expect(picked, [bytes]);
    expect(avatarButton, findsOneWidget);
    picker.result = null;

    await tap(avatarButton);
    await tap(find.text('Cancel'));
    expect(picker.calls, 2);
    expect(removals, 0);

    await tap(avatarButton);
    await tap(find.text('Remove image'));
    await tap(find.text('Cancel').hitTestable());
    expect(removals, 0);
    expect(find.text('Pick image'), findsOneWidget);

    await tap(find.text('Remove image'));
    await tap(find.text('Remove'));
    expect(removals, 1);
    expect(find.text('Pick image'), findsNothing);

    await tap(avatarButton);
    expect(picker.calls, 3);
    expect(find.text('Pick image'), findsNothing);
  });
}
