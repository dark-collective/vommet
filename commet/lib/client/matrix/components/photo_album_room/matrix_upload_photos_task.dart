import 'dart:async';
import 'package:commet/client/attachment.dart';
import 'package:commet/client/components/photo_album_room/photo_album_room_component.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/utils/background_tasks/background_task_manager.dart';
import 'package:exif/exif.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'package:image/image.dart' as img;

/// Prepares a picture for an album upload when "send original" is off: drops
/// EXIF and re-encodes it as JPEG. Animated images are sent unchanged (a
/// re-encode keeps only the first frame) and pictures with transparency become
/// PNG (JPEG has no alpha). Throws on data we can't decode, as before, rather
/// than uploading a file whose metadata we couldn't strip.
(Uint8List, String) prepareAlbumImage((Uint8List, String) input) {
  final (bytes, name) = input;
  final img.Image? image;
  try {
    final decoder = img.findDecoderForData(bytes);
    if (decoder == null) {
      throw UnsupportedError("Unsupported image format: $name");
    }

    // Counting frames only reads the headers, so big animations aren't
    // decoded.
    if ((decoder.startDecode(bytes)?.numFrames ?? 1) > 1) return input;

    image = decoder.decode(bytes);
  } on UnsupportedError {
    rethrow;
  } catch (e) {
    throw UnsupportedError("Could not decode image $name: $e");
  }
  if (image == null) {
    throw UnsupportedError("Could not decode image: $name");
  }

  image.exif.clear();
  final rawName = p.basenameWithoutExtension(name);
  if (_hasTransparency(image)) {
    return (img.encodePng(image), "$rawName.png");
  }
  return (img.encodeJpg(image, quality: 90), "$rawName.jpeg");
}

bool _hasTransparency(img.Image image) {
  if (!image.hasAlpha) return false;
  for (final pixel in image) {
    if (pixel.a < image.maxChannelValue) return true;
  }
  return false;
}

class MatrixUploadPhotosTask implements BackgroundTaskWithIntegerProgress {
  List<PickedPhoto> files;

  MatrixRoom room;
  bool extractMetadata;
  bool sendOriginal;

  BackgroundTaskStatus status = BackgroundTaskStatus.running;

  StreamController<int> progressStream = StreamController.broadcast();
  StreamController controller = StreamController.broadcast();

  MatrixUploadPhotosTask(this.files, this.room,
      {this.extractMetadata = true, this.sendOriginal = false}) {
    total = files.length;
  }

  @override
  void Function()? action;

  @override
  bool get canCallAction => false;

  @override
  int current = 0;

  @override
  void dispose() {}

  @override
  String get label => "Uploading Photos";

  @override
  Stream<int> get onProgress => progressStream.stream;

  @override
  bool shouldRemoveTask = false;

  @override
  Stream<void> get statusChanged => controller.stream;

  @override
  late int total;

  Future<void> uploadImages() async {
    for (var i = 0; i < files.length; i++) {
      var file = files[i];

      var name = file.name;
      print("Loading bytes");
      var imageData = await file.getBytes();
      print("Loaded bytes");
      Map<String, dynamic> extraInfo = {};

      if (extractMetadata) {
        Map<String, dynamic> exifInfo = {};

        print("Loading exif data");
        var exif = await readExifFromBytes(imageData);
        print("Finished loading exif");

        for (var key in [
          "EXIF DateTimeOriginal",
          "EXIF DateTimeDigitized",
          "Image DateTime",
        ]) {
          if (exif.containsKey(key)) {
            var exifData = exif[key];
            if (exifData == null) continue;

            if (exifData.tagType == "ASCII") {
              exifInfo[key] = {};

              exifInfo[key]["tag_type"] = exifData.tagType;
              exifInfo[key]["value"] = exifData.printable;
            }
          }
        }

        if (exifInfo.isNotEmpty) {
          extraInfo["chat.commet.exif"] = exifInfo;
        }
      }

      if (!sendOriginal) {
        (imageData, name) = await compute(prepareAlbumImage, (imageData, name));
        print("Finished encoding image");
      }

      var processed = await room.processAttachment(
          PendingFileAttachment(name: name, data: imageData));

      await room.sendMessage(
          processedAttachments: [processed!], fileExtraContent: extraInfo);
      current += 1;
      progressStream.add(current);
    }

    status = BackgroundTaskStatus.completed;
    controller.add(null);

    Timer(const Duration(seconds: 5), () {
      shouldRemoveTask = true;
      controller.add(null);
    });
  }
}
