import 'package:commet/config/preferences.dart';
import 'package:commet/ui/molecules/timeline_events/events/timeline_event_view_sticker.dart';
import 'package:flutter_test/flutter_test.dart';

// Vommet issue 620: the Sticker size setting sizes stickers, not GIFs.
void main() {
  test('stickers follow the setting', () {
    expect(TimelineEventViewSticker.stickerHeight(isGif: false, setting: 112),
        112);
  });

  test('GIFs keep the default size', () {
    expect(TimelineEventViewSticker.stickerHeight(isGif: true, setting: 112),
        Preferences.stickerSizeDefault);
  });

  test('out-of-range values are clamped', () {
    expect(TimelineEventViewSticker.stickerHeight(isGif: false, setting: 10),
        Preferences.stickerSizeMin);
    expect(TimelineEventViewSticker.stickerHeight(isGif: false, setting: 9000),
        Preferences.stickerSizeMax);
  });

  test('default stays at the old fixed size', () {
    expect(Preferences.stickerSizeDefault, 200);
  });
}
