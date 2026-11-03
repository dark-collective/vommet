import 'package:commet/client/client.dart';
import 'package:commet/client/components/component.dart';
import 'package:commet/client/components/invitation/invitation_component.dart';
import 'package:commet/client/permissions.dart';
import 'package:commet/ui/molecules/space_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Permissions extends Permissions {
  _Permissions(this.canInviteUser);

  @override
  final bool canInviteUser;
}

class _Invitations implements InvitationComponent {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

// Has an InvitationComponent only when [invitations] is set.
class _Client implements Client {
  _Client(this.invitations);

  final InvitationComponent? invitations;

  @override
  T? getComponent<T extends Component>() =>
      T == InvitationComponent ? invitations as T? : null;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Room implements Room {
  _Room({required bool canInvite, bool hasInvitations = true})
      : permissions = _Permissions(canInvite),
        client = _Client(hasInvitations ? _Invitations() : null);

  @override
  final Permissions permissions;

  @override
  final Client client;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  Future<List<String>> menuTexts(WidgetTester tester, Room room) async {
    late List<String> texts;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
      texts = roomListMenuTail(context, room).map((i) => i.text).toList();
      return const SizedBox();
    })));
    return texts;
  }

  testWidgets("the room list menu offers Invite above Copy link",
      (tester) async {
    final texts = await menuTexts(tester, _Room(canInvite: true));
    final invite = texts.indexOf("Invite people");
    expect(invite, isNot(-1));
    expect(texts[invite - 1], "",
        reason: "first in its group, after a divider");
    expect(texts[invite + 1], anyOf("Copy Link", "Copy link"));
  });

  testWidgets("no Invite without permission to invite", (tester) async {
    final texts = await menuTexts(tester, _Room(canInvite: false));
    expect(texts, isNot(contains("Invite people")));
  });

  testWidgets("no Invite when the client can't send invitations",
      (tester) async {
    final texts =
        await menuTexts(tester, _Room(canInvite: true, hasInvitations: false));
    expect(texts, isNot(contains("Invite people")));
  });
}
