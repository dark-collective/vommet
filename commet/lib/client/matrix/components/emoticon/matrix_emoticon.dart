import 'package:commet/client/matrix/matrix_mxc_image_provider.dart';
import 'package:flutter/widgets.dart';
import 'package:matrix/matrix.dart' as matrix;

import '../../../components/emoticon/emoticon.dart';

class MatrixEmoticon implements Emoticon {
  late MatrixMxcImage _image;
  late String? _shortcode;
  @override
  String get slug => ":${shortcode!}:";

  @override
  ImageProvider<Object> get image => _image;

  @override
  String? get shortcode => _shortcode;

  Uri emojiUrl;

  @override
  EmoticonUsage usage;

  EmoticonUsage packUsage;

  MatrixEmoticon(this.emojiUrl, matrix.Client client,
      {required this.packUsage,
      required String shortcode,
      required this.usage}) {
    _shortcode = shortcode;
    // Vommet: stickers fill ~125-190 dp picker tiles, ~500 px on a phone;
    // decoding them at 100 px (fine for inline emoji) made them blurry.
    // lod_image never decodes above the image's own height.
    _image = MatrixMxcImage(emojiUrl, client,
        fullResHeight: isSticker ? 512 : 100,
        doThumbnail: false,
        doFullres: true,
        autoLoadFullRes: true);
  }

  void setShortcode(String shortcode) {
    _shortcode = shortcode;
  }

  void setImage(MatrixMxcImage image) {
    _image = image;
  }

  @override
  String get key => emojiUrl.toString();

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    if (other is! MatrixEmoticon) {
      return false;
    }

    return other.key == this.key;
  }

  @override
  int get hashCode {
    return key.hashCode;
  }

  @override
  bool get isSticker =>
      usage == EmoticonUsage.sticker ||
      usage == EmoticonUsage.all ||
      (usage == EmoticonUsage.inherit &&
          [EmoticonUsage.sticker, EmoticonUsage.all].contains(packUsage));

  @override
  bool get isEmoji =>
      usage == EmoticonUsage.emoji ||
      usage == EmoticonUsage.all ||
      (usage == EmoticonUsage.inherit &&
          [EmoticonUsage.emoji, EmoticonUsage.all].contains(packUsage));
}
