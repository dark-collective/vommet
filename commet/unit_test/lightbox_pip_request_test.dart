import 'package:commet/cache/file_provider.dart';
import 'package:commet/ui/atoms/lightbox.dart';
import 'package:commet/ui/molecules/video_player/video_player_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Vommet issue 1080: picture in picture for a video that isn't tied to a
// message on screen (a gallery page, a mosaic tile, the Media tab).

class _File extends Fake implements FileProvider {}

void main() {
  test('the window keeps the viewer\'s player and opens its message', () {
    var backToMessage = 0;
    final key = GlobalKey();
    final request = Lightbox.pictureInPictureRequest(
      video: _File(),
      controller: VideoPlayerController(),
      playerKey: key,
      aspectRatio: 1.5,
      onBackToMessage: () => backToMessage++,
    );

    expect(request.aspectRatio, 1.5);
    expect(request.onExpand, isNotNull);
    request.onBackToMessage!();
    expect(backToMessage, 1);
  });

  test('no Back to message without a message to go to', () {
    final request = Lightbox.pictureInPictureRequest(
      video: _File(),
      controller: VideoPlayerController(),
      playerKey: GlobalKey(),
    );
    expect(request.onBackToMessage, isNull);
  });
}
