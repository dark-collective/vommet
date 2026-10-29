// Vommet issue 734: grouping a space's invite with its rooms' invites.

import 'package:commet/client/components/invitation/invite_grouping.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, List<String>> group(
  List<String> invites, {
  Set<String> spaces = const {},
  Set<String> direct = const {},
  Map<String, Set<String>> children = const {},
  List<String> joined = const [],
}) =>
    InviteGrouping.group(
        invites: invites,
        spaceInvites: spaces,
        directInvites: direct,
        childrenOf: children,
        joinedSpaces: joined);

void main() {
  test("an invited space takes the invites to its rooms, in list order", () {
    final groups = group(
      ["!b", "!space", "!a", "!other"],
      spaces: {"!space"},
      children: {
        "!space": {"!a", "!b", "!notinvited"}
      },
    );
    expect(groups, {
      "!space": ["!b", "!a"]
    });
  });

  test("an invited space without room invites is no group", () {
    expect(
        group([
          "!space",
          "!x"
        ], spaces: {
          "!space"
        }, children: {
          "!space": {"!y"}
        }),
        isEmpty);
  });

  test("an invited subspace and its rooms join the outer space's group", () {
    final groups = group(
      ["!sub", "!r2", "!outer", "!r1"],
      spaces: {"!outer", "!sub"},
      children: {
        "!outer": {"!sub", "!r1"},
        "!sub": {"!r2"},
      },
    );
    expect(groups, {
      "!outer": ["!sub", "!r2", "!r1"]
    });
  });

  test("direct-message invites are never grouped", () {
    final groups = group(
      ["!space", "!dm", "!room"],
      spaces: {"!space"},
      direct: {"!dm"},
      children: {
        "!space": {"!dm", "!room"}
      },
    );
    expect(groups, {
      "!space": ["!room"]
    });
  });

  test("a joined space groups two or more of its room invites", () {
    final children = {
      "!joined": {"!a", "!b"},
      "!small": {"!c"},
    };
    expect(
        group(["!a", "!b", "!c"],
            children: children, joined: ["!joined", "!small"]),
        {
          "!joined": ["!a", "!b"]
        });
  });

  test("an invited space wins over a joined space listing the same room", () {
    final groups = group(
      ["!space", "!a", "!b", "!c"],
      spaces: {"!space"},
      children: {
        "!space": {"!a"},
        "!joined": {"!a", "!b", "!c"},
      },
      joined: ["!joined"],
    );
    expect(groups, {
      "!space": ["!a"],
      "!joined": ["!b", "!c"],
    });
  });

  test("spaces listing each other don't loop", () {
    final groups = group(
      ["!s1", "!s2", "!r"],
      spaces: {"!s1", "!s2"},
      children: {
        "!s1": {"!s2"},
        "!s2": {"!s1", "!r"},
      },
    );
    expect(groups, {
      "!s1": ["!s2", "!r"]
    });
  });
}
