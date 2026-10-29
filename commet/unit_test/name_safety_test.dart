import 'package:commet/client/matrix/nicknames/name_safety.dart';
import 'package:test/test.dart';

void main() {
  // Vommet identity per place, phase 2: name safety (R1, R2).
  group('key', () {
    test('ignores case, spaces and separators', () {
      expect(NameSafety.key("Wren Feather"), NameSafety.key("wren_feather"));
      expect(NameSafety.key("W.R.E.N"), NameSafety.key("wren"));
    });

    test('Cyrillic and Greek lookalikes match Latin', () {
      // Cyrillic А and о.
      expect(NameSafety.key("Аlice"), NameSafety.key("Alice"));
      expect(NameSafety.key("Bоbby"), NameSafety.key("Bobby"));
      // Greek omicron.
      expect(NameSafety.key("Rοsa"), NameSafety.key("Rosa"));
    });

    test('digit and letter lookalikes match', () {
      expect(NameSafety.key("Bo0ker"), NameSafety.key("Booker"));
      expect(NameSafety.key("Wil1"), NameSafety.key("Will"));
      expect(NameSafety.key("Iris"), NameSafety.key("lris"));
      expect(NameSafety.key("Arnie"), NameSafety.key("Amie"));
    });

    test('zero-width and direction controls are ignored', () {
      expect(NameSafety.key("Wr\u200Ben"), NameSafety.key("Wren"));
      expect(NameSafety.key("\u202EWren"), NameSafety.key("Wren"));
    });

    test('fullwidth letters and accents match', () {
      expect(NameSafety.key("Ｗren"), NameSafety.key("Wren"));
      expect(NameSafety.key("Renée"), NameSafety.key("Renee"));
    });

    test('different names stay different', () {
      expect(NameSafety.key("Wren"), isNot(NameSafety.key("Bramble")));
      expect(NameSafety.key("Sol"), isNot(NameSafety.key("Sola")));
    });
  });

  group('flag', () {
    test('two members with lookalike names are both flagged', () {
      final flagged = NameSafety.flag([
        const NameSafetyEntry("@sol:a.org", "Sol"),
        const NameSafetyEntry("@sol:b.org", "Sоl"),
        const NameSafetyEntry("@wren:a.org", "Wren"),
      ], []);
      expect(flagged, {"@sol:a.org", "@sol:b.org"});
    });

    test('a member posing as a contact is flagged, the contact is not', () {
      final flagged = NameSafety.flag([
        const NameSafetyEntry("@fake:b.org", "Wren"),
        const NameSafetyEntry("@other:a.org", "Bramble"),
      ], [
        const NameSafetyEntry("@wren:a.org", "Wren"),
      ]);
      expect(flagged, {"@fake:b.org"});
    });

    test('the same person as member and contact is not a collision', () {
      final flagged = NameSafety.flag([
        const NameSafetyEntry("@wren:a.org", "Wren"),
      ], [
        const NameSafetyEntry("@wren:a.org", "Wren"),
      ]);
      expect(flagged, isEmpty);
    });

    test('trusted people are never flagged but are still checked against', () {
      final flagged = NameSafety.flag([
        const NameSafetyEntry("@me:a.org", "Wren"),
        const NameSafetyEntry("@copy:b.org", "wren"),
      ], [], trusted: {
        "@me:a.org"
      });
      expect(flagged, {"@copy:b.org"});
    });

    test('the same picture file is a collision (R2)', () {
      final flagged = NameSafety.flag([
        const NameSafetyEntry("@a:x.org", "Pine", "mxc://x.org/same"),
        const NameSafetyEntry("@b:y.org", "Lantern", "mxc://x.org/same"),
        const NameSafetyEntry("@c:y.org", "Moss", "mxc://x.org/other"),
      ], []);
      expect(flagged, {"@a:x.org", "@b:y.org"});
    });

    test('a contact picture reused by a member is a collision', () {
      final flagged = NameSafety.flag([
        const NameSafetyEntry("@b:y.org", "Lantern", "mxc://x.org/friend"),
      ], [
        const NameSafetyEntry("@friend:x.org", "Friend", "mxc://x.org/friend"),
      ]);
      expect(flagged, {"@b:y.org"});
    });

    test('members without a name are not matched by name', () {
      final flagged = NameSafety.flag([
        const NameSafetyEntry("@a:x.org", null),
        const NameSafetyEntry("@b:x.org", " "),
      ], []);
      expect(flagged, isEmpty);
    });
  });

  // Vommet identity per place, phase 3: role words and badges (R5).
  group('claimsRole', () {
    test('role words on their own count', () {
      for (final name in [
        "Admin",
        "Wren (mod)",
        "Wren [Moderator]",
        "Matrix Support",
        "Official Wren",
        "wren | staff",
        "Wren - Admins",
      ]) {
        expect(NameSafety.claimsRole(name), isTrue, reason: name);
      }
    });

    test('lookalike and hidden letters still count', () {
      // Cyrillic А, digit 0, zero-width space.
      expect(NameSafety.claimsRole("Аdmin"), isTrue);
      expect(NameSafety.claimsRole("Wren M0D"), isTrue);
      expect(NameSafety.claimsRole("Wren ad​min"), isTrue);
      expect(NameSafety.claimsRole("A.D.M.I.N"), isTrue);
    });

    test('check marks and shields count', () {
      expect(NameSafety.claimsRole("Wren ✓"), isTrue);
      expect(NameSafety.claimsRole("Wren ✔️"), isTrue);
      expect(NameSafety.claimsRole("✅ Wren"), isTrue);
      expect(NameSafety.claimsRole("🛡️Wren"), isTrue);
    });

    test('words that only contain a role word do not count', () {
      for (final name in [
        "Wren",
        "Modest Moss",
        "Badminton fan",
        "Supporter",
        "Staffordshire",
        "model",
      ]) {
        expect(NameSafety.claimsRole(name), isFalse, reason: name);
      }
    });
  });
}
