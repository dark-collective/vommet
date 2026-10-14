import 'dart:convert';

import 'package:commet/client/client.dart';
import 'package:commet/config/preferences/preference.dart';
import 'package:commet/ui/molecules/image_select_dialog.dart';
import 'package:commet/ui/pages/settings/categories/room/appearance/room_appearance_settings_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_dark.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class _Client extends Fake implements Client {}

final _png = MemoryImage(base64Decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="));

void main() {
  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    Preference.preferences = await SharedPreferences.getInstance();
  });

  Widget view({ImageProvider? avatar, Future<void> Function()? onRemoved}) {
    return MaterialApp(
      theme: ThemeDark.theme,
      home: Scaffold(
        body: RoomAppearanceSettingsView(
          avatar: avatar,
          client: _Client(),
          displayName: "Lounge",
          identifier: "!lounge:example.org",
          color: Colors.teal,
          canEditAvatar: true,
          onImageRemoved: onRemoved,
        ),
      ),
    );
  }

  ImageProvider? shownAvatar(WidgetTester tester) =>
      tester.widget<tiamat.ImageButton>(find.byType(tiamat.ImageButton)).image;

  testWidgets('an existing icon can be removed from the change image dialog',
      (tester) async {
    var removed = 0;
    await tester
        .pumpWidget(view(avatar: _png, onRemoved: () async => removed++));

    await tester.tap(find.byType(tiamat.ImageButton));
    await tester.pumpAndSettle();
    expect(find.byType(ImageSelectDialog), findsOneWidget);

    await tester.tap(find.text("Remove Image"));
    await tester.pumpAndSettle();
    // Confirmation dialog
    await tester.tap(find.text("Remove").last);
    await tester.pumpAndSettle();

    expect(removed, 1);
    expect(find.byType(ImageSelectDialog), findsNothing);
    expect(shownAvatar(tester), isNull);
  });

  testWidgets('cancelling the dialog keeps the icon', (tester) async {
    var removed = 0;
    await tester
        .pumpWidget(view(avatar: _png, onRemoved: () async => removed++));

    await tester.tap(find.byType(tiamat.ImageButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Cancel"));
    await tester.pumpAndSettle();

    expect(removed, 0);
    expect(shownAvatar(tester), _png);
  });

  testWidgets('an icon removed elsewhere disappears from the editor',
      (tester) async {
    await tester.pumpWidget(view(avatar: _png, onRemoved: () async {}));
    expect(shownAvatar(tester), _png);

    await tester.pumpWidget(view(avatar: null, onRemoved: () async {}));
    expect(shownAvatar(tester), isNull);
  });
}
