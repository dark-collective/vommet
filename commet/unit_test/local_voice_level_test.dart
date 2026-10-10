import 'package:commet/client/components/voip/local_voice_level.dart';
import 'package:test/test.dart';

void main() {
  // totalAudioEnergy grows by level² × seconds.
  double energy(double level, double seconds) => level * level * seconds;

  test("needs two readings", () {
    final v = LocalVoiceLevel();
    expect(v.update(0, 0), null);
    expect(v.update(energy(0.1, 0.1), 0.1), true);
  });

  test("a whisper counts, the noise floor doesn't", () {
    final v = LocalVoiceLevel();
    var e = 0.0, t = 0.0;
    v.update(e, t);
    // A whisper: about -40 dBFS.
    e += energy(0.01, 0.1);
    t += 0.1;
    expect(v.update(e, t), true);
    // What's left after noise suppression: about -60 dBFS.
    e += energy(0.001, 0.1);
    t += 0.1;
    expect(v.update(e, t), false);
  });

  test("a restarted track or missing stats start over", () {
    final v = LocalVoiceLevel();
    v.update(5, 10);
    expect(v.update(0, 0), null);
    expect(v.update(null, null), null);
    expect(v.update(0, 0), null);
    expect(v.update(energy(0.05, 0.1), 0.1), true);
  });
}
