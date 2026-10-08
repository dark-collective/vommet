import 'dart:typed_data';

import 'package:commet/client/client.dart';
import 'package:commet/client/components/room_component.dart';
import 'package:flutter/widgets.dart';

/// A banner image for an ordinary room, like the one spaces already have.
abstract class RoomBannerComponent<R extends Client, T extends Room>
    implements RoomComponent<R, T> {
  ImageProvider? get banner;

  bool get canEditBanner;

  /// Fires when the banner is set or removed, by us or by anyone else.
  Stream<void> get onBannerChanged;

  Future<void> setBanner(Uint8List data, {String? mimeType});
  Future<void> removeBanner();
}
