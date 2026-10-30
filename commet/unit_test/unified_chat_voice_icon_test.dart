// Vommet: in the unified chat list, a voice room's speaker icon is green only
// while people are in the call; an empty voice room uses the muted # colour
// (Vommet issue 469). Made-up names.
import 'package:commet/ui/organisms/unified_chat_list/unified_chat_model.dart';
import 'package:commet/ui/organisms/unified_chat_list/unified_chat_rows.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _green = Color(0xff23a55a);

ChatEntry _voiceRoom(int people) => ChatEntry(
    key: "acct:tabletop",
    roomId: "tabletop",
    name: "Tabletop",
    kind: ChatKind.voice,
    voiceCount: people);

Future<BuildContext> _context(WidgetTester tester) async {
  late BuildContext context;
  await tester.pumpWidget(MaterialApp(home: Builder(builder: (c) {
    context = c;
    return const SizedBox();
  })));
  return context;
}

Color? _speakerColor(WidgetTester tester) => tester
    .widget<Icon>(
        find.byWidgetPredicate((w) => w is Icon && w.icon == Icons.volume_up))
    .color;

void main() {
  testWidgets("an empty voice room's icon is muted, an active one green",
      (tester) async {
    final context = await _context(tester);
    final muted = Theme.of(context).colorScheme.secondary;

    final empty = chatKindIcon(context, ChatKind.voice) as Icon;
    expect(empty.color, muted);
    final active =
        chatKindIcon(context, ChatKind.voice, voiceActive: true) as Icon;
    expect(active.color, _green);
    final room = chatKindIcon(context, ChatKind.room) as Icon;
    expect(room.color, muted);
  });

  testWidgets("a voice room chip is green only while people are in the call",
      (tester) async {
    final context = await _context(tester);
    final muted = Theme.of(context).colorScheme.secondary;

    await tester
        .pumpWidget(MaterialApp(home: Scaffold(body: RoomChip(_voiceRoom(0)))));
    expect(_speakerColor(tester), muted);

    await tester
        .pumpWidget(MaterialApp(home: Scaffold(body: RoomChip(_voiceRoom(2)))));
    expect(_speakerColor(tester), _green);
  });
}
