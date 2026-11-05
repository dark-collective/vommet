// Vommet (New Home): tab icons beyond the 16 built-in ones — the icon
// catalog and its search, emoji and uploaded pictures (Vommet issue 698).
import 'dart:typed_data';

import 'package:commet/ui/organisms/new_home/new_home.dart';
import 'package:commet/ui/organisms/new_home/new_home_editor.dart';
import 'package:commet/ui/organisms/new_home/new_home_icon_catalog.dart';
import 'package:commet/ui/organisms/new_home/new_home_tab_icon.dart';
import 'package:commet/ui/organisms/new_home/new_home_tabs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  group("Icon catalog", () {
    test("names are unique and every category has icons", () {
      final names = homeIconCatalog.map((e) => e.name).toList();
      expect(names.toSet().length, names.length);
      expect(names.length, greaterThan(400));
      for (final (i, category) in homeIconCategories.indexed) {
        expect(
            homeIconCatalog.where((e) => e.categories & (1 << i) != 0).length,
            greaterThan(20),
            reason: category);
      }
      expect(homeIconCatalog.every((e) => e.categories != 0), isTrue);
    });

    test("labels read as words", () {
      final entry =
          homeIconCatalog.firstWhere((e) => e.name == "sports_esports");
      expect(entry.label, "Sports esports");
    });
  });

  group("homeTabIcon", () {
    test("built-in names keep their glyphs", () {
      expect(homeTabIcon("gamepad"), Icons.sports_esports_rounded);
      expect(homeTabIcon(HomeTabs.defaultIcon), Icons.dashboard_rounded);
    });

    test("catalog icons by m: name", () {
      expect(homeTabIcon(catalogTabIcon("casino")), Icons.casino_rounded);
    });

    test("unknown names, emoji and pictures draw the default", () {
      expect(homeTabIcon("m:no_such_icon"), Icons.dashboard_rounded);
      expect(homeTabIcon(emojiTabIcon("🎲")), Icons.dashboard_rounded);
      expect(homeTabIcon("mxc://example.org/abc"), Icons.dashboard_rounded);
    });

    test("kinds", () {
      expect(tabIconEmoji("e:🎲"), "🎲");
      expect(tabIconEmoji("e:"), isNull);
      expect(tabIconEmoji("gamepad"), isNull);
      expect(isImageTabIcon("mxc://example.org/abc"), isTrue);
      expect(isImageTabIcon("m:casino"), isFalse);
    });
  });

  group("searchHomeIcons", () {
    List<String> names(String query, {int? category}) =>
        searchHomeIcons(query, category: category).map((e) => e.name).toList();

    test("an empty query lists the category", () {
      expect(names("").length, homeIconCatalog.length);
      final games = homeIconCategories.indexOf("Games");
      expect(names("", category: games), contains("sports_esports"));
      expect(names("", category: games), isNot(contains("restaurant")));
    });

    test("names first, then keywords", () {
      expect(names("casino").first, "casino");
      expect(names("dice"), contains("casino"));
      expect(names("SPORTS esp"), contains("sports_esports"));
      expect(names("zzzz-nothing"), isEmpty);
    });

    test("a name match ranks above a keyword match", () {
      final found = names("pizza");
      expect(found.first, "local_pizza");
    });
  });

  group("Uploaded pictures", () {
    test("are cropped square and shrunk", () {
      final wide = img.Image(width: 300, height: 200);
      img.fill(wide, color: img.ColorRgb8(200, 40, 40));
      final png = squareTabIconPng(img.encodePng(wide));
      expect(png, isNotNull);
      final out = img.decodePng(png!)!;
      expect(out.width, tabIconPixels);
      expect(out.height, tabIconPixels);
    });

    test("anything else is refused", () {
      expect(squareTabIconPng(Uint8List.fromList([1, 2, 3, 4])), isNull);
    });

    test("the used-before list", () {
      expect(recentTabImagesFrom(null), isEmpty);
      expect(recentTabImagesFrom({"recent": "nope"}), isEmpty);
      expect(
          recentTabImagesFrom({
            "recent": ["mxc://a/1", 5, "https://a/2", "mxc://a/1", "mxc://a/3"]
          }),
          ["mxc://a/1", "mxc://a/3"]);
      final full = [for (var i = 0; i < maxRecentTabImages; i++) "mxc://a/$i"];
      final next = withRecentTabImage(full, "mxc://a/new");
      expect(next.first, "mxc://a/new");
      expect(next.length, maxRecentTabImages);
      expect(next, isNot(contains("mxc://a/${maxRecentTabImages - 1}")));
      expect(withRecentTabImage(["mxc://a/1", "mxc://a/2"], "mxc://a/2"),
          ["mxc://a/2", "mxc://a/1"]);
    });
  });

  group("Picking an icon", () {
    Future<TabFormResult?> openForm(WidgetTester tester,
        {HomeTab? editing, required Future<void> Function() act}) async {
      tester.view.physicalSize = const Size(1000, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      TabFormResult? result;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  result = await showDialog<TabFormResult>(
                    context: context,
                    builder: (_) => Dialog(
                      child: SingleChildScrollView(
                        child: HomeTabForm(
                            current: HomeTabs.defaultTab(HomeTabs.overview)!,
                            removedDefaults: const [],
                            editing: editing),
                      ),
                    ),
                  );
                },
                child: const Text("open"),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text("open"));
      await tester.pumpAndSettle();
      await act();
      await tester
          .ensureVisible(find.byKey(const ValueKey("NewHomeTabSubmit")));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey("NewHomeTabSubmit")));
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets("More icons: search, pick, use", (tester) async {
      final result = await openForm(tester, act: () async {
        await tester.enterText(
            find.byKey(const ValueKey("NewHomeTabName")), "Board games");
        expect(find.text("Upload image"), findsOneWidget);
        expect(
            find.byKey(const ValueKey("NewHomeTabIcon-picked")), findsNothing);
        await tester.tap(find.byKey(const ValueKey("NewHomeTabMoreIcons")));
        await tester.pumpAndSettle();
        expect(find.text("Choose an icon"), findsOneWidget);
        await tester.enterText(
            find.byKey(const ValueKey("NewHomeIconSearch")), "dice");
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey("NewHomeIcon-casino")));
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey("NewHomeIconUse")));
        await tester.pumpAndSettle();
        expect(find.text("Choose an icon"), findsNothing);
        // The picked icon stays in sight, selected.
        expect(find.byKey(const ValueKey("NewHomeTabIcon-picked")),
            findsOneWidget);
      });
      expect(result?.name, "Board games");
      expect(result?.icon, "m:casino");
    });

    testWidgets("a category narrows the icons", (tester) async {
      await openForm(tester, act: () async {
        await tester.tap(find.byKey(const ValueKey("NewHomeTabMoreIcons")));
        await tester.pumpAndSettle();
        final food = homeIconCategories.indexOf("Food");
        await tester.tap(find.byKey(ValueKey("NewHomeIconCategory-$food")));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey("NewHomeIcon-restaurant")),
            findsOneWidget);
        expect(find.byKey(const ValueKey("NewHomeIcon-sports_esports")),
            findsNothing);
        await tester.tap(find.text("Cancel").last);
        await tester.pumpAndSettle();
        await tester.enterText(
            find.byKey(const ValueKey("NewHomeTabName")), "Food");
      });
    });

    testWidgets("an existing picked icon shows as its own tile",
        (tester) async {
      final result = await openForm(tester,
          editing: const HomeTab("tab-a", name: "Games", icon: "m:casino"),
          act: () async {
        expect(find.text("Rename and icon"), findsOneWidget);
        expect(find.byKey(const ValueKey("NewHomeTabIcon-picked")),
            findsOneWidget);
      });
      expect(result?.icon, "m:casino");
    });
  });
}
