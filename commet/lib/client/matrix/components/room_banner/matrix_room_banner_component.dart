import 'dart:async';
import 'dart:typed_data';

import 'package:commet/client/components/room_banner/room_banner_component.dart';
import 'package:commet/client/matrix/components/matrix_sync_listener.dart';
import 'package:commet/client/matrix/components/space_banner/matrix_space_banner_component.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/matrix_mxc_image_provider.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:flutter/widgets.dart';
import 'package:matrix/matrix.dart' as matrix;

/// Room banners use the same state event as space banners
/// (`page.codeberg.everypizza.room.banner`), so they interoperate with other
/// clients that already read it.
class MatrixRoomBannerComponent
    implements
        RoomBannerComponent<MatrixClient, MatrixRoom>,
        MatrixRoomSyncListener {
  static const String key = MatrixSpaceBannerComponent.key;

  @override
  MatrixClient client;

  @override
  MatrixRoom room;

  final StreamController<void> _onBannerChanged = StreamController.broadcast();

  MatrixRoomBannerComponent(this.client, this.room);

  @override
  Stream<void> get onBannerChanged => _onBannerChanged.stream;

  @override
  ImageProvider<Object>? get banner {
    final state = room.matrixRoom.getState(key);
    if (state == null) return null;

    final url = state.content["url"];
    if (url is! String || !url.startsWith("mxc://")) return null;

    return MatrixMxcImage(Uri.parse(url), client.matrixClient);
  }

  @override
  bool get canEditBanner => room.matrixRoom.canChangeStateEvent(key);

  @override
  Future<void> setBanner(Uint8List data, {String? mimeType}) async {
    final uri =
        await client.matrixClient.uploadContent(data, contentType: mimeType);

    await client.matrixClient.setRoomStateWithKey(
      room.matrixRoom.id,
      key,
      '',
      {
        'url': uri.toString(),
        if (mimeType != null) 'mimetype': mimeType,
      },
    );
    _onBannerChanged.add(null);
  }

  @override
  Future<void> removeBanner() async {
    await client.matrixClient
        .setRoomStateWithKey(room.matrixRoom.id, key, '', {});
    _onBannerChanged.add(null);
  }

  @override
  onSync(matrix.JoinedRoomUpdate update) {
    final events = [
      ...?update.state,
      ...?update.timeline?.events,
    ];
    if (events.any((e) => e.type == key)) {
      _onBannerChanged.add(null);
    }
  }
}
