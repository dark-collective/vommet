import 'dart:io';

import 'package:commet/ui/pages/settings/categories/account/security/matrix/key_file/key_file_row.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Models file_picker 10.x's FilePickerIO.saveFile: Android and iOS reject a
/// call without bytes ("Bytes are required on Android & iOS when saving a
/// file.") and save the bytes themselves; desktop only returns a path.
class FakeFilePicker extends FilePicker {
  FakeFilePicker(this.path);
  final String? path;
  Uint8List? savedBytes;
  int calls = 0;

  @override
  Future<String?> saveFile(
      {String? dialogTitle,
      String? fileName,
      String? initialDirectory,
      FileType type = FileType.any,
      List<String>? allowedExtensions,
      Uint8List? bytes,
      bool lockParentWindow = false}) async {
    calls++;
    final mobile = defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android;
    if (mobile) {
      if (bytes == null) {
        throw ArgumentError(
            'Bytes are required on Android & iOS when saving a file.');
      }
      savedBytes = bytes;
    }
    return path;
  }
}

void main() {
  final bytes =
      Uint8List.fromList("-----BEGIN MEGOLM SESSION DATA-----".codeUnits);
  const name = "vommet-keys-2026-11-02.txt";

  tearDown(() => debugDefaultTargetPlatformOverride = null);

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    test("$platform hands the key file bytes to the save dialog", () async {
      debugDefaultTargetPlatformOverride = platform;
      final picker = FakeFilePicker("/picked/$name");
      FilePicker.platform = picker;

      final path = await saveKeyFile(name, bytes);

      expect(path, "/picked/$name");
      expect(picker.savedBytes, bytes);
    });
  }

  test("iOS: a cancelled save dialog returns null", () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    FilePicker.platform = FakeFilePicker(null);
    expect(await saveKeyFile(name, bytes), isNull);
  });

  test("desktop picks a path and writes the file itself", () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    final dir = await Directory.systemTemp.createTemp("key_file_save_test");
    addTearDown(() => dir.delete(recursive: true));
    final target = "${dir.path}/$name";
    final picker = FakeFilePicker(target);
    FilePicker.platform = picker;

    final path = await saveKeyFile(name, bytes);

    expect(path, target);
    expect(picker.calls, 1);
    expect(await File(target).readAsBytes(), bytes);
  });
}
