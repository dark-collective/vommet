import 'package:commet/ui/atoms/voice_room_occupancy.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// A voice room with a picture: headphones beside the picture, no ring, a
/// bold name while people are in the call; and a darker green on light
/// themes (readable on the light sidebar).
void main() {
  for (final brightness in Brightness.values) {
    testWidgets("voice room row draws (${brightness.name})", (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(brightness: brightness),
        home: Material(
          child: Builder(
            builder: (context) => tiamat.TextButton(
              "Sunset Lounge",
              avatarPlaceholderText: "Sunset Lounge",
              avatarPlaceholderColor: Colors.teal,
              avatarBadge: Icons.headphones,
              avatarBadgeColor: VoiceRoomOccupancy.greenFor(context),
              avatarGlyphBeside: true,
              bold: true,
              maxLines: 2,
              softwrap: true,
              onTap: () {},
            ),
          ),
        ),
      ));
      expect(tester.takeException(), isNull);
      expect(find.byType(tiamat.AvatarRing), findsOneWidget);
      expect(
          find.descendant(
              of: find.byType(tiamat.AvatarRing),
              matching: find.byType(CustomPaint)),
          findsNothing,
          reason: "no ring");
      final name = tester.widget<Text>(find.text("Sunset Lounge"));
      expect(name.style?.fontWeight, FontWeight.w700);
      final glyph = tester.widget<Icon>(find.byIcon(Icons.headphones));
      expect(
          glyph.color,
          brightness == Brightness.light
              ? VoiceRoomOccupancy.greenOnLight
              : VoiceRoomOccupancy.green);
    });
  }
}
