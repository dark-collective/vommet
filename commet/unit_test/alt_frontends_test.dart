// Vommet issue 727: links to well-known services open on the
// privacy-friendly frontend the user picked, only when turned on.
import 'dart:math';

import 'package:commet/main.dart';
import 'package:commet/utils/links/alt_frontends.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
  });

  AltFrontendService service(String id) => AltFrontends.serviceById(id)!;

  Future<void> turnOn(String id, List<String> instances) async {
    await preferences.altFrontendsEnabled.set(true);
    await AltFrontends.setServiceOn(service(id), true);
    await AltFrontends.setSelectedInstances(service(id), instances);
  }

  String? rewrite(String url) =>
      AltFrontends.rewrite(Uri.parse(url))?.uri.toString();

  test('nothing is rewritten by default', () async {
    expect(AltFrontends.enabled, isFalse);
    expect(rewrite("https://www.youtube.com/watch?v=abc"), isNull);
  });

  test('a service needs the setting, its switch and an instance', () async {
    await AltFrontends.setServiceOn(service("youtube"), true);
    await AltFrontends.setSelectedInstances(
        service("youtube"), ["inv.example.org"]);
    expect(rewrite("https://www.youtube.com/watch?v=abc"), isNull);

    await preferences.altFrontendsEnabled.set(true);
    expect(rewrite("https://www.youtube.com/watch?v=abc"),
        "https://inv.example.org/watch?v=abc");

    await AltFrontends.setServiceOn(service("youtube"), false);
    expect(rewrite("https://www.youtube.com/watch?v=abc"), isNull);
  });

  test('YouTube links keep the video and start time', () async {
    await turnOn("youtube", ["inv.example.org"]);
    expect(rewrite("https://youtu.be/abc?t=42"),
        "https://inv.example.org/watch?v=abc&t=42");
    expect(rewrite("https://m.youtube.com/shorts/xyz"),
        "https://inv.example.org/shorts/xyz");
    expect(rewrite("https://music.youtube.com/watch?v=abc&list=L"),
        "https://inv.example.org/watch?v=abc&list=L");
    expect(rewrite("https://youtu.be/"), isNull);
  });

  test('other services map to their frontend paths', () async {
    await turnOn("twitter", ["nitter.example.net"]);
    await turnOn("reddit", ["redlib.example.com"]);
    await turnOn("medium", ["scribe.example.dev"]);
    await turnOn("fandom", ["breeze.example.org"]);

    expect(rewrite("https://x.com/someone/status/1"),
        "https://nitter.example.net/someone/status/1");
    expect(rewrite("https://old.reddit.com/r/test/comments/a1/b/"),
        "https://redlib.example.com/r/test/comments/a1/b/");
    expect(rewrite("https://redd.it/a1"),
        "https://redlib.example.com/comments/a1");
    expect(rewrite("https://someone.medium.com/a-post-123"),
        "https://scribe.example.dev/@someone/a-post-123");
    expect(rewrite("https://minecraft.fandom.com/wiki/Creeper"),
        "https://breeze.example.org/minecraft/wiki/Creeper");
  });

  test('unrelated hosts and look-alikes are left alone', () async {
    await turnOn("youtube", ["inv.example.org"]);
    await turnOn("reddit", ["redlib.example.com"]);
    expect(rewrite("https://notyoutube.com/watch?v=abc"), isNull);
    expect(rewrite("https://i.redd.it/picture.png"), isNull);
    expect(rewrite("mailto:someone@youtube.com"), isNull);
  });

  test('several instances: one is picked at random per link', () async {
    await turnOn("youtube", ["a.example", "b.example"]);
    final picks = {
      for (var i = 0; i < 20; i++)
        AltFrontends.rewrite(Uri.parse("https://youtu.be/abc"),
                random: Random(i))!
            .instance
    };
    expect(picks, {"a.example", "b.example"});
  });

  test('user-added instances are normalized and listed', () async {
    expect(AltFrontends.normalizeInstance(" https://Inv.Mine.org/path "),
        "inv.mine.org");
    expect(AltFrontends.normalizeInstance("inv.mine.org:8443"),
        "inv.mine.org:8443");
    expect(AltFrontends.normalizeInstance("not a host"), isNull);
    expect(AltFrontends.normalizeInstance("ftp://inv.mine.org"), isNull);

    await AltFrontends.addCustomInstance(service("youtube"), "inv.mine.org");
    expect(AltFrontends.allInstances(service("youtube")),
        contains("inv.mine.org"));
    expect(AltFrontends.customInstances(service("twitter")), isEmpty);

    await turnOn("youtube", ["inv.mine.org:8443"]);
    expect(rewrite("https://youtu.be/abc"),
        "https://inv.mine.org:8443/watch?v=abc");

    await AltFrontends.removeCustomInstance(service("youtube"), "inv.mine.org");
    expect(AltFrontends.customInstances(service("youtube")), isEmpty);
  });
}
