// Vommet issue 175: YouTube links play inside Vommet through the Invidious
// instance picked for YouTube (Vommet issue 727), only when turned on.
import 'package:commet/main.dart';
import 'package:commet/utils/links/alt_frontends.dart';
import 'package:commet/utils/links/invidious_playback.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
  });

  Future<void> turnOnYoutube(List<String> instances) async {
    final youtube = AltFrontends.serviceById("youtube")!;
    await preferences.altFrontendsEnabled.set(true);
    await AltFrontends.setServiceOn(youtube, true);
    await AltFrontends.setSelectedInstances(youtube, instances);
  }

  (String, bool)? parse(String url) => InvidiousPlayback.parse(Uri.parse(url));

  test('video ids come from every YouTube link shape', () {
    expect(parse("https://www.youtube.com/watch?v=aB3cD4eF5gH&t=42"),
        ("aB3cD4eF5gH", false));
    expect(parse("https://youtu.be/aB3cD4eF5gH?t=1"), ("aB3cD4eF5gH", false));
    expect(parse("https://m.youtube.com/shorts/aB3cD4eF5gH"),
        ("aB3cD4eF5gH", true));
    expect(parse("https://www.youtube.com/live/aB3cD4eF5gH"),
        ("aB3cD4eF5gH", false));
    expect(parse("https://www.youtube-nocookie.com/embed/aB3cD4eF5gH"),
        ("aB3cD4eF5gH", false));
    expect(parse("https://music.youtube.com/watch?v=aB3cD4eF5gH"),
        ("aB3cD4eF5gH", false));
  });

  test('channels, playlists, bad ids and other sites are not videos', () {
    expect(parse("https://www.youtube.com/@someone"), isNull);
    expect(parse("https://www.youtube.com/playlist?list=PL1"), isNull);
    expect(parse("https://www.youtube.com/watch?v=short"), isNull);
    expect(parse("https://example.com/watch?v=aB3cD4eF5gH"), isNull);
  });

  test('playback needs the YouTube frontend and its own switch', () async {
    final link = Uri.parse("https://youtu.be/aB3cD4eF5gH");
    expect(InvidiousPlayback.videoFor(link), isNull);

    await turnOnYoutube(["inv.example.org"]);
    final video = InvidiousPlayback.videoFor(link)!;
    expect(video.instance, "inv.example.org");
    expect(video.stream.toString(),
        "https://inv.example.org/latest_version?id=aB3cD4eF5gH&itag=18&local=true");

    await preferences.altFrontendsYoutubePlayback.set(false);
    expect(InvidiousPlayback.videoFor(link), isNull);
  });

  test('only a picked instance plays without the remote video prompt',
      () async {
    expect(InvidiousPlayback.isPickedInstance("inv.example.org"), isFalse);
    await turnOnYoutube(["inv.example.org", "inv.other.net:8443"]);
    expect(InvidiousPlayback.isPickedInstance("inv.example.org"), isTrue);
    expect(InvidiousPlayback.isPickedInstance("inv.other.net"), isTrue);
    expect(InvidiousPlayback.isPickedInstance("evil.example.com"), isFalse);
  });

  test('a Short plays in a portrait frame', () async {
    await turnOnYoutube(["inv.example.org"]);
    final short = InvidiousPlayback.videoFor(
        Uri.parse("https://youtube.com/shorts/aB3cD4eF5gH"))!;
    final attachment = short.attachment();
    expect(attachment.height! > attachment.width!, isTrue);
    expect(attachment.streamUrl, short.stream);
  });
}
