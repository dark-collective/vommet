import 'dart:async';

import 'package:commet/client/components/friends/friends_component.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/organisms/new_home/new_home.dart';
import 'package:commet/ui/organisms/user_profile/profile_contact_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Vommet: the profile card's Add contact / Contact button (New Home only).

class _Friends implements FriendsComponent {
  @override
  final Set<String> friends = {};
  final changes = StreamController<void>.broadcast();
  final added = <String>[];
  final removed = <String>[];

  @override
  Stream<void> get onFriendsChanged => changes.stream;

  @override
  Future<void> addFriends(Iterable<String> userIds) async {
    added.addAll(userIds);
    friends.addAll(userIds);
    changes.add(null);
  }

  @override
  Future<void> removeFriend(String userId) async {
    removed.add(userId);
    friends.remove(userId);
    changes.add(null);
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

const _id = "@juniper:example.org";

void main() {
  late _Friends friends;
  late List<String> opened;

  Future<void> load({required bool newHome}) async {
    // unit_test/ isn't a directory the analyzer counts as tests.
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    // Set after loading: loading clears a stored "off" once (New Home is on
    // for everyone since 10-25).
    await experimentNewHome.set(newHome);
  }

  setUp(() {
    friends = _Friends();
    opened = [];
  });

  Future<void> pump(WidgetTester tester) => tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: ProfileContactButton(
              friends: friends,
              userId: _id,
              displayName: "Juniper",
              onOpenPeople: (_) => opened.add("people"),
            ),
          ),
        ),
      ));

  testWidgets("hidden while New Home is off", (tester) async {
    await load(newHome: false);
    await pump(tester);
    expect(find.byKey(ProfileContactButton.addKey), findsNothing);
    expect(find.byKey(ProfileContactButton.contactKey), findsNothing);
    expect(find.text("Add contact"), findsNothing);
  });

  testWidgets("shows up when New Home is switched on", (tester) async {
    await load(newHome: false);
    await pump(tester);
    await experimentNewHome.set(true);
    await tester.pump();
    expect(find.text("Add contact"), findsOneWidget);
  });

  testWidgets("Add contact for someone who isn't one, full width",
      (tester) async {
    await load(newHome: true);
    await pump(tester);
    expect(find.text("Add contact"), findsOneWidget);
    expect(find.byIcon(Icons.person_add), findsOneWidget);
    expect(tester.getSize(find.byKey(ProfileContactButton.addKey)).width,
        400 - 16);
  });

  testWidgets("adding shows a toast whose Undo removes them again",
      (tester) async {
    await load(newHome: true);
    await pump(tester);
    await tester.tap(find.byKey(ProfileContactButton.addKey));
    await tester.pump();
    await tester.pump();
    expect(friends.added, [_id]);
    expect(find.text("Added Juniper to your contacts."), findsOneWidget);
    expect(find.text("Contact"), findsOneWidget);

    await tester.tap(find.byKey(ProfileContactButton.undoKey));
    await tester.pump();
    expect(friends.removed, [_id]);
    expect(find.text("Added Juniper to your contacts."), findsNothing);
    expect(find.text("Add contact"), findsOneWidget);
  });

  testWidgets("the toast goes away by itself", (tester) async {
    await load(newHome: true);
    await pump(tester);
    await tester.tap(find.byKey(ProfileContactButton.addKey));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(ProfileContactButton.undoKey), findsOneWidget);
    await tester.pump(ProfileContactToast.duration + Durations.short1);
    expect(find.byKey(ProfileContactButton.undoKey), findsNothing);
    expect(friends.removed, isEmpty);
  });

  testWidgets("a contact gets the Contact menu: remove and open People",
      (tester) async {
    await load(newHome: true);
    friends.friends.add(_id);
    await pump(tester);
    expect(find.text("Add contact"), findsNothing);
    expect(find.text("Contact"), findsOneWidget);
    expect(find.byIcon(Icons.how_to_reg_rounded), findsOneWidget);
    expect(find.byIcon(Icons.arrow_drop_down), findsOneWidget);

    await tester.tap(find.byKey(ProfileContactButton.contactKey));
    await tester.pumpAndSettle();
    expect(find.text("Remove from contacts"), findsOneWidget);
    expect(find.text("Open People"), findsOneWidget);

    await tester.tap(find.byKey(ProfileContactButton.openPeopleKey));
    await tester.pumpAndSettle();
    expect(opened, ["people"]);

    await tester.tap(find.byKey(ProfileContactButton.contactKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ProfileContactButton.removeKey));
    await tester.pumpAndSettle();
    expect(friends.removed, [_id]);
    expect(find.text("Add contact"), findsOneWidget);
  });

  testWidgets("follows changes made elsewhere", (tester) async {
    await load(newHome: true);
    await pump(tester);
    expect(find.text("Add contact"), findsOneWidget);

    friends.friends.add(_id);
    friends.changes.add(null);
    await tester.pumpAndSettle();
    expect(find.text("Contact"), findsOneWidget);

    friends.friends.remove(_id);
    friends.changes.add(null);
    await tester.pumpAndSettle();
    expect(find.text("Add contact"), findsOneWidget);
  });
}
