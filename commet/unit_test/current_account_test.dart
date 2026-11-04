import 'package:commet/client/client.dart';
import 'package:commet/client/components/profile/profile_component.dart';
import 'package:commet/ui/molecules/account_selector.dart';
import 'package:commet/utils/current_account.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeProfile implements Profile {
  _FakeProfile(this.displayName);

  @override
  final String displayName;

  @override
  String get detail => "@$displayName:example.org";

  @override
  ImageProvider? get avatar => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeClient implements Client {
  _FakeClient(this.identifier) : self = _FakeProfile("name-$identifier");

  @override
  final String identifier;

  @override
  Profile? self;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final a = _FakeClient("a");
  final b = _FakeClient("b");
  final c = _FakeClient("c");
  final clients = <Client>[a, b, c];

  group("currentAccount", () {
    test("returns the account the app is switched to", () {
      expect(currentAccount(clients, "b"), same(b));
      expect(currentAccount(clients, "c"), same(c));
    });

    test("falls back to the first account when showing all accounts", () {
      expect(currentAccount(clients, null), same(a));
    });

    test("falls back to the first account when the selected one is gone", () {
      expect(currentAccount(clients, "signed-out"), same(a));
    });

    test("is null without accounts", () {
      expect(currentAccount([], "a"), isNull);
      expect(currentAccount([], null), isNull);
    });
  });

  group("currentAccountFirst", () {
    test("moves the current account to the front, keeps the rest in order", () {
      expect(currentAccountFirst(clients, "c"), [c, a, b]);
      expect(currentAccountFirst(clients, "b"), [b, a, c]);
    });

    test("keeps the order when the first account is current", () {
      expect(currentAccountFirst(clients, null), [a, b, c]);
      expect(currentAccountFirst(clients, "a"), [a, b, c]);
    });

    test("does not change the list it is given", () {
      currentAccountFirst(clients, "c");
      expect(clients, [a, b, c]);
    });

    test("handles no accounts", () {
      expect(currentAccountFirst([], "a"), isEmpty);
    });
  });

  group("AccountSelector", () {
    Widget host(Client? initial) => MaterialApp(
          home: Scaffold(
            body: AccountSelector(clients, initialClient: initial),
          ),
        );

    testWidgets("shows the initial account as selected", (tester) async {
      await tester.pumpWidget(host(b));
      expect(find.text("name-b"), findsOneWidget);
      expect(find.text("name-a"), findsNothing);
    });

    testWidgets("shows the first account without an initial one",
        (tester) async {
      await tester.pumpWidget(host(null));
      expect(find.text("name-a"), findsOneWidget);
      expect(find.text("name-b"), findsNothing);
    });

    testWidgets("shows the first account when the initial one is not listed",
        (tester) async {
      await tester.pumpWidget(host(_FakeClient("other")));
      expect(find.text("name-a"), findsOneWidget);
    });
  });
}
