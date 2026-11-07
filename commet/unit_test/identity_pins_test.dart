import 'dart:convert';

import 'package:commet/client/matrix/identity_pins.dart';
import 'package:commet/config/preferences/preference.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:shared_preferences/shared_preferences.dart';

class _FakeClient extends Fake implements matrix.Client {
  @override
  final Map<String, matrix.DeviceKeysList> userDeviceKeys = {};

  @override
  String? get userID => "@me:example.org";
}

class _FakeDevice extends Fake implements matrix.DeviceKeys {}

const _them = "@them:example.org";
const _pinKey = "@me:example.org|$_them";

void main() {
  // A pinned identity whose master key disappears must not look like
  // "never set up secure messaging".
  late _FakeClient client;

  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    Preference.preferences = await SharedPreferences.getInstance();
    IdentityPins.resetForTest();
    client = _FakeClient();
  });

  Future<void> pin() async {
    await Preference.preferences!
        .setString("vommet_identity_pins", jsonEncode({_pinKey: "MASTER"}));
    IdentityPins.resetForTest();
  }

  matrix.DeviceKeysList keysWithoutMaster({required bool fetched}) {
    final keys = matrix.DeviceKeysList(_them, client);
    if (fetched) {
      keys.outdated = false;
      keys.deviceKeys = {"EVIL": _FakeDevice()};
    }
    client.userDeviceKeys[_them] = keys;
    return keys;
  }

  test('no keys at all is unknown', () {
    expect(IdentityPins.check(client, _them), PeerIdentity.unknown);
  });

  test('no master key and nothing pinned is "not set up"', () {
    keysWithoutMaster(fetched: true);
    expect(IdentityPins.check(client, _them), PeerIdentity.notSetUp);
  });

  test('a pinned identity that has gone counts as changed', () async {
    await pin();
    keysWithoutMaster(fetched: true);
    expect(IdentityPins.check(client, _them), PeerIdentity.changed);
  });

  test('a pinned identity whose keys are not fetched yet is unknown', () async {
    await pin();
    keysWithoutMaster(fetched: false);
    expect(IdentityPins.check(client, _them), PeerIdentity.unknown);
  });

  test('an outdated list that already has devices is still changed', () async {
    await pin();
    keysWithoutMaster(fetched: true).outdated = true;
    expect(IdentityPins.check(client, _them), PeerIdentity.changed);
  });

  test('"It was them" without a master key forgets the pin', () async {
    await pin();
    keysWithoutMaster(fetched: true);
    await IdentityPins.acknowledge(client, _them);
    expect(IdentityPins.check(client, _them), PeerIdentity.notSetUp);
    final stored =
        jsonDecode(Preference.preferences!.getString("vommet_identity_pins")!)
            as Map;
    expect(stored.containsKey(_pinKey), isFalse);
  });
}
