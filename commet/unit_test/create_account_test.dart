import 'dart:io';

import 'package:commet/client/matrix/auth/matrix_registration.dart';
import 'package:commet/client/matrix/auth/recommended_homeservers.dart';
import 'package:flutter_test/flutter_test.dart';

// Vommet issue 254: "Create an account".
void main() {
  group("recommended homeservers", () {
    test("the bundled list parses, nether.im first and marked as ours", () {
      final list = RecommendedHomeserver.parseList(
          File("assets/data/homeservers.json").readAsStringSync());

      expect(list, isNotEmpty);
      expect(list.first.server, "nether.im");
      expect(list.first.us, isTrue);
      expect(list.first.registration, HomeserverRegistration.invite);
      expect(list.where((s) => s.us), hasLength(1));
      for (final server in list) {
        expect(server.summary, isNotEmpty, reason: server.server);
      }
    });

    test("entries this version can't use are skipped", () {
      final list = RecommendedHomeserver.parseList('''
        {"servers": [
          {"server": "a.example", "summary": "A", "registration": "open"},
          {"server": "b.example", "summary": "B", "registration": "lottery"},
          {"summary": "no server", "registration": "open"},
          "not an object"
        ]}''');

      expect(list.map((s) => s.server), ["a.example"]);
      expect(list.single.calls, isFalse);
      expect(list.single.tags, isEmpty);
    });

    test("a malformed file gives an empty list", () {
      expect(RecommendedHomeserver.parseList('{"servers": 3}'), isEmpty);
      expect(RecommendedHomeserver.parseList('[]'), isEmpty);
    });
  });

  group("registration flow choice", () {
    test("picks the shortest flow made of stages the app supports", () {
      expect(
          chooseRegistrationFlow([
            ["m.login.registration_token", "m.login.email.identity"],
            ["m.login.registration_token", "m.login.terms", "m.login.dummy"],
            ["m.login.registration_token", "m.login.dummy"],
          ]),
          ["m.login.registration_token", "m.login.dummy"]);
    });

    test("no usable flow when every flow needs email", () {
      expect(
          chooseRegistrationFlow([
            [
              "m.login.registration_token",
              "m.login.recaptcha",
              "m.login.email.identity"
            ],
          ]),
          isNull);
    });

    test("reCAPTCHA is usable through the web fallback", () {
      expect(
          chooseRegistrationFlow([
            ["m.login.recaptcha", "m.login.terms"]
          ]),
          ["m.login.recaptcha", "m.login.terms"]);
    });
  });

  test("terms policies come out with their names and links", () {
    final policies = registrationPolicies({
      "m.login.terms": {
        "policies": {
          "privacy": {
            "version": "1.0",
            "en": {"name": "Privacy Policy", "url": "https://hs.example/p"},
          },
          "rules": {
            "version": "2",
            "de": {"name": "Regeln", "url": "https://hs.example/r"},
          },
        }
      }
    });

    expect(policies, [
      ("Privacy Policy", Uri.parse("https://hs.example/p")),
      ("Regeln", Uri.parse("https://hs.example/r")),
    ]);
    expect(registrationPolicies({}), isEmpty);
  });

  test("web fallback URL follows the spec", () {
    expect(
        registrationFallbackUrl(
                Uri.parse("https://matrix.hs.example"), recaptchaStage, "abc")
            .toString(),
        "https://matrix.hs.example/_matrix/client/v3/auth/m.login.recaptcha/fallback/web?session=abc");
  });
}
