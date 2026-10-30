import 'package:commet/utils/stun_server_url.dart';
import 'package:test/test.dart';

// Vommet issue 563: the fallback STUN server field only accepts one STUN URL.
void main() {
  test('accepts stun: and stuns: URLs', () {
    expect(isValidStunServerUrl("stun:turn.matrix.org"), isTrue);
    expect(isValidStunServerUrl("stun:stun.example.org:3478"), isTrue);
    expect(isValidStunServerUrl("stuns:stun.example.org:5349"), isTrue);
    expect(isValidStunServerUrl("STUN:stun.example.org"), isTrue);
    expect(isValidStunServerUrl("stun:[2001:db8::1]:3478"), isTrue);
    expect(isValidStunServerUrl("  stun:stun.example.org  "), isTrue);
  });

  test('rejects anything else', () {
    expect(isValidStunServerUrl(""), isFalse);
    expect(isValidStunServerUrl("stun:"), isFalse);
    expect(isValidStunServerUrl("stun.example.org"), isFalse);
    expect(isValidStunServerUrl("turn:turn.example.org"), isFalse);
    expect(isValidStunServerUrl("https://stun.example.org"), isFalse);
    expect(isValidStunServerUrl("stun://stun.example.org"), isFalse);
    expect(isValidStunServerUrl("stun:a.org stun:b.org"), isFalse);
    expect(
        isValidStunServerUrl("stun:stun.example.org?transport=udp"), isFalse);
  });
}
