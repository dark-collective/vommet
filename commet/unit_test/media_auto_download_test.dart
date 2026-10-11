import 'package:commet/config/preferences/preference.dart';
import 'package:commet/main.dart';
import 'package:commet/utils/media_auto_download.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  // Vommet issue 75: automatic media download per connection type.
  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    Preference.preferences = await SharedPreferences.getInstance();
    MediaAutoDownload.resetForTest(network: MediaNetwork.mobile);
  });

  test('policy JSON round trip, and broken values mean everything on', () {
    const policy = AutoDownloadPolicy(photos: false, videoPreviews: false);
    expect(AutoDownloadPolicy.fromJson(policy.toJson()), policy);
    expect(AutoDownloadPolicy.fromJson(""), const AutoDownloadPolicy());
    expect(AutoDownloadPolicy.fromJson("{nope"), const AutoDownloadPolicy());
    expect(AutoDownloadPolicy.fromJson('{"photos": "x"}'),
        const AutoDownloadPolicy());
  });

  test('a turned-off policy allows nothing', () {
    const off = AutoDownloadPolicy(enabled: false);
    for (final kind in AutoMediaKind.values) {
      expect(off.allows(kind), isFalse);
    }
    expect(const AutoDownloadPolicy(gifs: false).allows(AutoMediaKind.gif),
        isFalse);
    expect(const AutoDownloadPolicy(gifs: false).allows(AutoMediaKind.photo),
        isTrue);
  });

  test('kinds of event media', () {
    expect(MediaAutoDownload.kindOf(eventType: "m.sticker"), AutoMediaKind.gif);
    expect(
        MediaAutoDownload.kindOf(
            eventType: "m.room.message",
            msgtype: "m.image",
            mimetype: "image/png"),
        AutoMediaKind.photo);
    expect(
        MediaAutoDownload.kindOf(
            eventType: "m.room.message",
            msgtype: "m.image",
            mimetype: "image/gif"),
        AutoMediaKind.gif);
    expect(
        MediaAutoDownload.kindOf(
            eventType: "m.room.message", msgtype: "m.video"),
        AutoMediaKind.videoPreview);
    expect(
        MediaAutoDownload.kindOf(
            eventType: "m.room.message", msgtype: "m.file"),
        isNull);
    expect(MediaAutoDownload.kindOf(eventType: "m.room.member"), isNull);
  });

  test('network from connectivity results', () {
    expect(MediaAutoDownload.networkFrom([ConnectivityResult.wifi]),
        MediaNetwork.wifi);
    expect(
        MediaAutoDownload.networkFrom(
            [ConnectivityResult.vpn, ConnectivityResult.wifi]),
        MediaNetwork.wifi);
    expect(MediaAutoDownload.networkFrom([ConnectivityResult.ethernet]),
        MediaNetwork.wifi);
    expect(MediaAutoDownload.networkFrom([ConnectivityResult.mobile]),
        MediaNetwork.mobile);
    expect(
        MediaAutoDownload.networkFrom(
            [ConnectivityResult.vpn, ConnectivityResult.mobile]),
        MediaNetwork.mobile);
    expect(MediaAutoDownload.networkFrom([ConnectivityResult.none]),
        MediaNetwork.wifi);
  });

  test('defaults let everything through', () async {
    await MediaAutoDownload.waitUntilAllowed("mxc://a/1", AutoMediaKind.photo);
    expect(MediaAutoDownload.held.value, isEmpty);
  });

  test('held media loads once revealed', () async {
    await MediaAutoDownload.setPolicy(
        MediaNetwork.mobile, const AutoDownloadPolicy(photos: false));
    var done = false;
    MediaAutoDownload.waitUntilAllowed("mxc://a/1", AutoMediaKind.photo)
        .then((_) => done = true);
    await Future<void>.delayed(Duration.zero);
    expect(done, isFalse);
    expect(MediaAutoDownload.held.value, {"mxc://a/1"});

    MediaAutoDownload.reveal("mxc://a/1");
    await Future<void>.delayed(Duration.zero);
    expect(done, isTrue);
    expect(MediaAutoDownload.held.value, isEmpty);

    // Revealed media doesn't wait again.
    await MediaAutoDownload.waitUntilAllowed("mxc://a/1", AutoMediaKind.photo);
  });

  test('joining Wi-Fi or changing the policy releases held media', () async {
    await MediaAutoDownload.setPolicy(
        MediaNetwork.mobile, const AutoDownloadPolicy(enabled: false));
    var photo = false;
    var gif = false;
    MediaAutoDownload.waitUntilAllowed("p", AutoMediaKind.photo)
        .then((_) => photo = true);
    MediaAutoDownload.waitUntilAllowed("g", AutoMediaKind.gif)
        .then((_) => gif = true);
    await Future<void>.delayed(Duration.zero);
    expect(MediaAutoDownload.held.value, {"p", "g"});

    await MediaAutoDownload.setPolicy(
        MediaNetwork.mobile, const AutoDownloadPolicy(gifs: false));
    await Future<void>.delayed(Duration.zero);
    expect(photo, isTrue);
    expect(gif, isFalse);

    MediaAutoDownload.setNetworkForTest(MediaNetwork.wifi);
    await Future<void>.delayed(Duration.zero);
    expect(gif, isTrue);
    expect(MediaAutoDownload.held.value, isEmpty);
    expect(preferences.autoDownloadMobile.value, isNotEmpty);
  });
}
