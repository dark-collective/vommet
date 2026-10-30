import 'package:commet/client/matrix/matrix_membership.dart';
import 'package:commet/client/member.dart';
import 'package:commet/ui/molecules/user_list.dart';
import 'package:flutter_test/flutter_test.dart';

class _Member extends Fake implements Member {
  _Member(this.identifier);

  @override
  final String identifier;
}

List<String> _ids(List<Member> members) =>
    members.map((m) => m.identifier).toList();

void main() {
  final alice = _Member("@alice:a");
  final bob = _Member("@bob:a");
  final carol = _Member("@carol:a");

  group("refreshedPlainMembers (Vommet issue 341)", () {
    test("drops a kicked member kept from the earlier fetch", () {
      final result = refreshedPlainMembers(
        current: [alice],
        previous: [alice, bob, carol],
        complete: false,
        hasLeft: (id) => id == bob.identifier,
        roleHolderIds: const {},
      );
      expect(_ids(result), ["@alice:a", "@carol:a"]);
    });

    test("keeps earlier members the room holds no member event for", () {
      final result = refreshedPlainMembers(
        current: [alice],
        previous: [bob],
        complete: false,
        hasLeft: (_) => false,
        roleHolderIds: const {},
      );
      expect(_ids(result), ["@alice:a", "@bob:a"]);
    });

    test("a complete list is the room's own, nothing carried over", () {
      final result = refreshedPlainMembers(
        current: [alice],
        previous: [alice, bob],
        complete: true,
        hasLeft: (_) => false,
        roleHolderIds: const {},
      );
      expect(_ids(result), ["@alice:a"]);
    });

    test("role holders are left to their own sections", () {
      final result = refreshedPlainMembers(
        current: [alice, bob],
        previous: [carol],
        complete: false,
        hasLeft: (_) => false,
        roleHolderIds: {alice.identifier, carol.identifier},
      );
      expect(_ids(result), ["@bob:a"]);
    });

    test("doesn't change the room's list it was given", () {
      final current = <Member>[alice];
      refreshedPlainMembers(
        current: current,
        previous: [bob],
        complete: false,
        hasLeft: (_) => false,
        roleHolderIds: {alice.identifier},
      );
      expect(_ids(current), ["@alice:a"]);
    });
  });

  group("matrixMembershipHasLeft", () {
    test("leave (left or kicked) and ban are gone", () {
      expect(matrixMembershipHasLeft("leave"), isTrue);
      expect(matrixMembershipHasLeft("ban"), isTrue);
    });

    test("joined, invited, knocking or unknown are still there", () {
      expect(matrixMembershipHasLeft("join"), isFalse);
      expect(matrixMembershipHasLeft("invite"), isFalse);
      expect(matrixMembershipHasLeft("knock"), isFalse);
      expect(matrixMembershipHasLeft(null), isFalse);
    });
  });
}
