import 'package:commet/config/preferences/preference.dart';
import 'package:commet/utils/gif_video.dart';
import 'package:commet/utils/media_auto_download.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    Preference.preferences = await SharedPreferences.getInstance();
    MediaAutoDownload.resetForTest(network: MediaNetwork.mobile);
  });

  test("mautrix GIF flags mark a video as a GIF", () {
    expect(
        isGifVideoInfo({
          "mimetype": "video/mp4",
          "fi.mau.gif": true,
          "fi.mau.loop": true,
          "fi.mau.autoplay": true,
          "fi.mau.hide_controls": true,
          "fi.mau.no_audio": true,
        }),
        isTrue);
    expect(isGifVideoInfo({"fi.mau.loop": true}), isTrue);
  });

  test("ordinary videos are not GIFs", () {
    expect(isGifVideoInfo({"mimetype": "video/mp4", "size": 1234}), isFalse);
    expect(isGifVideoInfo({"fi.mau.gif": false}), isFalse);
    expect(isGifVideoInfo({"fi.mau.gif": "true"}), isFalse);
  });

  test("GIF videos only start by themselves when GIFs may download", () async {
    expect(MediaAutoDownload.allowsNow(AutoMediaKind.gif), isTrue);
    await MediaAutoDownload.setPolicy(
        MediaNetwork.mobile, const AutoDownloadPolicy(gifs: false));
    expect(MediaAutoDownload.allowsNow(AutoMediaKind.gif), isFalse);
    MediaAutoDownload.setNetworkForTest(MediaNetwork.wifi);
    expect(MediaAutoDownload.allowsNow(AutoMediaKind.gif), isTrue);
  });
}
