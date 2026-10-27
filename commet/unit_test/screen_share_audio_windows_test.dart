// Vommet: the screen-share audio choice as capture options on Windows, where
// "All apps" also leaves out voice chat apps by exe name.

import 'package:commet/client/components/voip/screen_share_audio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test("All apps leaves out voice chat exes on Windows only", () {
    final windows = ScreenShareAudio.system.toCaptureOptions(windows: true)!;
    final linux = ScreenShareAudio.system.toCaptureOptions(windows: false)!;
    final winRules = windows['exclude'] as List;
    final linuxRules = linux['exclude'] as List;
    expect(winRules, contains({'application.process.binary': 'Discord.exe'}));
    expect(winRules, contains({'application.name': 'Discord'}));
    expect(
      winRules.length,
      ScreenShareAudio.voiceChatApps.length +
          ScreenShareAudio.windowsVoiceChatBinaries.length,
    );
    expect(linuxRules.length, ScreenShareAudio.voiceChatApps.length);
    expect(windows.containsKey('include'), isFalse);
  });

  test("an app picked from a Windows source list is its exe", () {
    final apps = ScreenShareAudio.appsFrom([
      {
        'index': 4120,
        'applicationName': 'Spotify',
        'binary': 'Spotify.exe',
        'pid': '4120',
        'isSelf': false,
      },
      {
        'index': 4188,
        'applicationName': 'Spotify',
        'binary': 'Spotify.exe',
        'pid': '4188',
        'isSelf': false,
      },
      {
        'index': 900,
        'applicationName': 'Vommet',
        'binary': 'vommet.exe',
        'pid': '900',
        'isSelf': true,
      },
    ]);
    expect(apps, hasLength(1));
    expect(apps.single.label, 'Spotify');
    expect(apps.single.toCaptureOptions(windows: true), {
      'include': [
        {'application.process.binary': 'Spotify.exe'}
      ],
    });
  });

  test("no audio sends no options", () {
    expect(ScreenShareAudio.none.toCaptureOptions(windows: true), isNull);
  });
}
