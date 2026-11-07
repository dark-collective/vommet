import 'dart:typed_data';

import 'package:commet/utils/picker_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';

class _GalleryPicker extends ImagePickerPlatform {
  XFile? image;
  final sources = <ImageSource>[];

  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async {
    sources.add(source);
    return image;
  }
}

void main() {
  test('iOS picks an image from the gallery and honors cancellation', () async {
    final originalPicker = ImagePickerPlatform.instance;
    final originalPlatform = debugDefaultTargetPlatformOverride;
    addTearDown(() {
      ImagePickerPlatform.instance = originalPicker;
      debugDefaultTargetPlatformOverride = originalPlatform;
    });

    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final bytes = Uint8List.fromList([1, 2, 3]);
    final gallery = _GalleryPicker()
      ..image = XFile.fromData(bytes, path: '/photo.png');
    ImagePickerPlatform.instance = gallery;

    final picked = await PickerUtils.pickImage();
    expect(gallery.sources, [ImageSource.gallery]);
    expect(picked?.name, 'photo.png');
    expect(await picked?.readAsBytes(), bytes);

    gallery.image = null;
    expect(await PickerUtils.pickImage(), isNull);
    expect(gallery.sources, [ImageSource.gallery, ImageSource.gallery]);
  });
}
