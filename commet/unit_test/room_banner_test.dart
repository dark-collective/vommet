import 'dart:typed_data';

import 'package:commet/client/matrix/components/room_banner/matrix_room_banner_component.dart';
import 'package:commet/ui/molecules/room_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// A valid 1x1 PNG.
final _png = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0xF8, 0xCF, 0xC0, 0xF0,
  0x1F, 0x00, 0x05, 0x00, 0x01, 0xFF, 0x89, 0x99, 0x3D, 0x1D, 0x00, 0x00,
  0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

Widget _app(Widget child) => MaterialApp(home: Scaffold(body: child));

/// The desktop room layout: chat Expanded, side panel a plain Row child with
/// an unbounded width, as in main_page_view_desktop.dart.
Widget _desktopRow(Widget banner) => _app(Row(children: [
      const Expanded(child: Text("chat")),
      Column(children: [
        banner,
        const SizedBox(width: 200, height: 100, child: Text("members")),
      ]),
    ]));

void main() {
  group("bannerUri", () {
    test("reads an mxc url", () {
      final uri = MatrixRoomBannerComponent.bannerUri(
          {"url": "mxc://nether.im/abc", "mimetype": "image/png"});
      expect(uri, Uri.parse("mxc://nether.im/abc"));
    });

    test("no event, or a removed banner", () {
      expect(MatrixRoomBannerComponent.bannerUri(null), isNull);
      expect(MatrixRoomBannerComponent.bannerUri({}), isNull);
    });

    test("ignores urls that are not mxc", () {
      for (final url in [
        "https://example.com/a.png",
        "mxc://",
        "mxc://nether.im",
        "mxc://nether.im/",
        42,
        "",
      ]) {
        expect(MatrixRoomBannerComponent.bannerUri({"url": url}), isNull,
            reason: "$url");
      }
    });
  });

  group("RoomBannerView", () {
    testWidgets("no banner takes no space", (tester) async {
      await tester.pumpWidget(
          _desktopRow(const RoomBannerView(null, name: "Room", width: 216)));
      expect(tester.takeException(), isNull);
      expect(find.byType(Image), findsNothing);
      expect(tester.getSize(find.byType(RoomBannerView)), Size.zero);
    });

    // Regression: the banner asked for an infinite width inside the desktop
    // side panel, layout threw, and the whole room view went blank.
    testWidgets("unbounded side panel uses the given width", (tester) async {
      await tester.pumpWidget(_desktopRow(
          RoomBannerView(MemoryImage(_png), name: "Room", width: 216)));
      expect(tester.takeException(), isNull);
      expect(find.text("chat"), findsOneWidget);
      expect(tester.getSize(find.byType(Image)), const Size(216, 100));
    });

    testWidgets("unbounded with no width draws nothing instead of throwing",
        (tester) async {
      await tester.pumpWidget(
          _desktopRow(RoomBannerView(MemoryImage(_png), name: "Room")));
      expect(tester.takeException(), isNull);
      expect(find.byType(Image), findsNothing);
      expect(find.text("chat"), findsOneWidget);
    });

    testWidgets("bounded parent: fills its width, space-header height",
        (tester) async {
      await tester.pumpWidget(_app(Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
              width: 320,
              child: RoomBannerView(MemoryImage(_png),
                  name: "Room", width: 216)))));
      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(Image)), const Size(320, 100));
    });

    testWidgets("shows the room's name over the image", (tester) async {
      await tester.pumpWidget(_desktopRow(
          RoomBannerView(MemoryImage(_png), name: "Light Chat", width: 216)));
      expect(find.text("Light Chat"), findsOneWidget);
    });

    testWidgets("a broken image keeps the header, without erroring",
        (tester) async {
      await tester.pumpWidget(_desktopRow(RoomBannerView(
          MemoryImage(Uint8List.fromList([1, 2, 3])),
          name: "Room",
          width: 216)));
      await tester
          .runAsync(() => Future.delayed(const Duration(milliseconds: 200)));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text("chat"), findsOneWidget);
      expect(find.text("Room"), findsOneWidget);
      expect(
          find.descendant(
              of: find.byType(Image), matching: find.byType(RawImage)),
          findsNothing);
    });
  });
}
