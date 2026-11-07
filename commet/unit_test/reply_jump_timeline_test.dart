// Vommet issue 1057: tapping a reply jumped up and down, stopped abruptly and
// sometimes left the message too low. These drive the real chat timeline
// (Chat + RoomTimelineWidgetView) on a phone-sized screen; only the
// homeserver is a stub. Each test prints `@@TRACE` lines (one per frame) and
// `@@RUN` lines with what it measured. The gate-only render test calls
// [replyJumpTests] with a [Snap] to take screenshots of the same runs.
import 'package:commet/client/client.dart';
import 'package:commet/client/client_manager.dart';
import 'package:commet/client/matrix/components/profile/matrix_profile_component.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/config/layout_style.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/molecules/room_timeline_widget/room_timeline_widget_view.dart';
import 'package:commet/ui/molecules/timeline_events/timeline_view_entry.dart';
import 'package:commet/ui/organisms/chat/chat.dart';
import 'package:commet/utils/emoji/unicode_emoji.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_dark.dart';

import 'roomlist_fixture.dart';

const a = "!a:example.com";

/// A phone (logical pixels, like a 6.1" Android/iOS phone).
const phone = Size(390, 844);

matrix.MatrixEvent message(String id, int n, {String? body}) =>
    matrix.MatrixEvent(
      type: matrix.EventTypes.Message,
      content: {"msgtype": "m.text", "body": body ?? "body $id"},
      // Alternate senders so rows aren't all grouped into one.
      senderId: n.isEven ? "@bob:example.com" : "@carol:example.com",
      eventId: id,
      originServerTs: DateTime.fromMillisecondsSinceEpoch(1700000100000 + n),
    );

/// An edit that makes [target] many lines tall: the row grows after the jump
/// the way a picture or link preview does once it loads.
matrix.MatrixEvent growEdit(String target, int n, int sender) {
  final body = List.generate(22, (i) => "grown line $i").join("\n");
  return matrix.MatrixEvent(
    type: matrix.EventTypes.Message,
    content: {
      "msgtype": "m.text",
      "body": "* $body",
      "m.new_content": {"msgtype": "m.text", "body": body},
      "m.relates_to": {"rel_type": "m.replace", "event_id": target},
    },
    senderId: sender.isEven ? "@bob:example.com" : "@carol:example.com",
    eventId: "\$edit$n",
    originServerTs: DateTime.fromMillisecondsSinceEpoch(1700000200000 + n),
  );
}

const customMix = LayoutOptions(
  oneChatList: true,
  captionBelow: false,
  limitWidth: false,
  bubbles: true,
  ownSide: OwnBubbleSide.right,
  avatarAtBottom: true,
);

final layouts = <(String, LayoutOptions?)>[
  ("Discord", LayoutOptions.discord),
  ("Telegram", LayoutOptions.telegram),
  ("Custom-mix", customMix),
];

class Frame {
  Frame(this.ms, this.offset, this.top, this.height, this.opacity,
      this.centerError);
  final int ms;
  final double offset;
  final double? top;
  final double? height;
  final double opacity;
  final double? centerError;

  @override
  String toString() {
    final o = offset.toStringAsFixed(1);
    final t = top?.toStringAsFixed(1);
    final h = height?.toStringAsFixed(1);
    final f = opacity.toStringAsFixed(2);
    final c = centerError?.toStringAsFixed(1);
    return "$ms $o $t $h $f $c";
  }
}

/// Takes a screenshot named [name] of the chat (the RepaintBoundary keyed
/// [chatKey]).
typedef Snap = Future<void> Function(WidgetTester tester, String name);

const chatKey = ValueKey("reply-jump-chat");

/// Real time given to the database between frames of a /context jump.
const realPause = Duration(milliseconds: 5);

/// Messages the timeline hasn't loaded, served by /context around $old20.
matrix.MatrixEvent oldMessage(int n) => matrix.MatrixEvent(
      type: matrix.EventTypes.Message,
      content: {"msgtype": "m.text", "body": "old body $n"},
      senderId: n.isEven ? "@bob:example.com" : "@carol:example.com",
      eventId: "\$old$n",
      originServerTs: DateTime.fromMillisecondsSinceEpoch(1690000000000 + n),
    );

void main() => replyJumpTests();

/// [prepare] runs before the chat is pumped (the render test loads fonts),
/// [snap] at the frames worth a screenshot, [only] picks tests by name.
void replyJumpTests(
    {Snap? snap,
    Future<void> Function(WidgetTester tester)? prepare,
    bool Function(String name)? only}) {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late MatrixClient client;
  late Timeline timeline;
  var n = 0;

  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    await UnicodeEmojis.load();
    client = await signedInClient("reply-jump-${n++}");
    client.self = MatrixProfile(client, matrix.Profile(userId: me));
    clientManager = ClientManager();
    await sync(
      client,
      join: {
        a: matrix.JoinedRoomUpdate(
          state: roomState(a),
          timeline: matrix.TimelineUpdate(
            events: [for (var i = 0; i < 80; i++) message("\$e$i", i)],
            prevBatch: "p",
          ),
        ),
      },
    );
    timeline = await client.getRoom(a)!.getTimeline();
  });

  tearDown(() async {
    contextResponse = null;
    clientManager = null;
    await timeline.close();
    await client.getMatrixClient().dispose(closeDatabase: true);
  });

  RoomTimelineWidgetViewState view(WidgetTester tester) => tester
      .state<RoomTimelineWidgetViewState>(find.byType(RoomTimelineWidgetView));

  Future<void> pumpChat(WidgetTester tester, LayoutOptions? layout,
      {bool custom = false}) async {
    if (prepare != null) await prepare(tester);
    if (layout != null) await layout.save();
    await layoutStyleCustomPicked.set(custom);
    tester.view.physicalSize = phone;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final chat = SizedBox.expand(child: Chat(client.getRoom(a)!));
    await tester.pumpWidget(MaterialApp(
      theme: ThemeDark.theme,
      home: Scaffold(body: RepaintBoundary(key: chatKey, child: chat)),
    ));
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }
    expect(view(tester).firstFrame, isFalse);
  }

  GlobalKey? keyOf(WidgetTester tester, String id) {
    for (final (key, eventId) in view(tester).eventKeys) {
      if (eventId == id) return key;
    }
    return null;
  }

  Rect? scrollViewport(WidgetTester tester) {
    final position = view(tester).controller.position;
    final context = position.context.notificationContext;
    final box = context?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  Rect? rowRect(WidgetTester tester, String id) {
    final context = keyOf(tester, id)?.currentContext;
    final box = context?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  // What the user sees of the row: the product of the fades above it.
  double opacityOf(WidgetTester tester, String id) {
    final context = keyOf(tester, id)?.currentContext;
    if (context == null) return 1;
    var opacity = 1.0;
    context.visitAncestorElements((element) {
      final widget = element.widget;
      if (widget is FadeTransition) opacity *= widget.opacity.value;
      if (widget is Opacity) opacity *= widget.opacity;
      return true;
    });
    return opacity;
  }

  Frame frame(WidgetTester tester, String id, int ms) {
    final row = rowRect(tester, id);
    final viewport = scrollViewport(tester);
    final shown = row != null && viewport != null && viewport.overlaps(row);
    return Frame(
      ms,
      view(tester).controller.offset,
      row?.top,
      row?.height,
      opacityOf(tester, id),
      shown ? row.center.dy - viewport.center.dy : null,
    );
  }

  // [snapAt]: frame times (ms) to screenshot; [snapOpaque]: screenshot the
  // first frame the target is shown fully opaque; [realWait]: give the
  // database a moment of real time before each frame (a /context load reads
  // it, and it doesn't run on the test's fake clock).
  Future<List<Frame>> record(WidgetTester tester, String id, String name,
      {int frames = 90,
      int start = 0,
      Set<int> snapAt = const {},
      bool snapOpaque = false,
      bool realWait = false}) async {
    final trace = <Frame>[];
    var opaqueShot = false;
    for (var i = 1; i <= frames; i++) {
      if (realWait) {
        await tester.runAsync(() => Future<void>.delayed(realPause));
      }
      await tester.pump(const Duration(milliseconds: 16));
      final f = frame(tester, id, start + i * 16);
      trace.add(f);
      // ignore: avoid_print
      print("@@TRACE $name $f");
      if (snap == null) continue;
      if (snapAt.contains(f.ms)) await snap(tester, "$name-${f.ms}ms");
      if (snapOpaque &&
          !opaqueShot &&
          f.centerError != null &&
          f.opacity >= .99) {
        opaqueShot = true;
        await snap(tester, "$name-opaque-${f.ms}ms");
      }
    }
    return trace;
  }

  void test(String name, Future<void> Function(WidgetTester) body) {
    if (only == null || only(name)) testWidgets(name, body);
  }

  // A nearby reply: the row nearest the top of the view at the bottom of the
  // chat, so centering it scrolls up about half a screen.
  String nearTarget(WidgetTester tester) {
    final top = scrollViewport(tester)!.top;
    String? best;
    double? bestDistance;
    for (final (_, id) in view(tester).eventKeys) {
      final row = rowRect(tester, id);
      if (row == null || row.height == 0) continue;
      final distance = (row.top - top).abs();
      if (bestDistance == null || distance < bestDistance) {
        best = id;
        bestDistance = distance;
      }
    }
    return best!;
  }

  // A far reply: the oldest loaded message, whose row isn't built.
  String farTarget(WidgetTester tester) {
    final id = view(tester).timeline.events.last.eventId;
    expect(rowRect(tester, id), isNull, reason: "not built: a far jump");
    return id;
  }

  Set<String> highlightedRows(WidgetTester tester) {
    final ids = <String>{};
    for (final (key, id) in view(tester).eventKeys) {
      final state = key.currentState;
      if (state is TimelineViewEntryState && state.highlighted) ids.add(id);
    }
    return ids;
  }

  Future<void> deliver(WidgetTester tester, matrix.MatrixEvent event) async {
    final update = matrix.JoinedRoomUpdate(
        timeline: matrix.TimelineUpdate(events: [event], prevBatch: "q"));
    await tester.runAsync(() => sync(client, join: {a: update}));
  }

  // The SDK's member lookups leave a one-minute timer, the message box its
  // keyboard height timers.
  Future<void> finish(WidgetTester tester) async {
    final error = tester.takeException();
    expect(error == null || error is MissingPluginException, isTrue);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 2));
  }

  void expectMonotonic(List<double> values, String what) {
    final up = values.last >= values.first;
    for (var i = 1; i < values.length; i++) {
      final step = values[i] - values[i - 1];
      expect(up ? step : -step, greaterThanOrEqualTo(-0.5),
          reason: "$what reversed at frame $i: "
              "${values[i - 1].toStringAsFixed(1)} -> "
              "${values[i].toStringAsFixed(1)}");
    }
  }

  void expectFullyShown(Rect row, Rect viewport) {
    if (row.height > viewport.height) {
      expect(row.top, closeTo(viewport.top, 1.5),
          reason: "a target taller than the view shows its top");
    } else {
      expect(row.top, greaterThanOrEqualTo(viewport.top - 1),
          reason: "top cut off: row $row, view $viewport");
      expect(row.bottom, lessThanOrEqualTo(viewport.bottom + 1),
          reason: "bottom cut off: row $row, view $viewport");
    }
  }

  for (final (layout, options) in layouts) {
    test("$layout: a nearby reply glides there and stops centered",
        (tester) async {
      await pumpChat(tester, options, custom: layout == "Custom-mix");
      final target = nearTarget(tester);
      final before = frame(tester, target, 0);
      // ignore: avoid_print
      print("@@TRACE near-$layout $before");
      await snap?.call(tester, "near-$layout-0ms");

      view(tester).jumpToEvent(target);
      final trace = await record(tester, target, "near-$layout",
          snapAt: {16, 48, 144, 448, 1440});

      final tops = [before.top!, for (final f in trace) f.top!];
      final offsets = [before.offset, for (final f in trace) f.offset];
      expectMonotonic(tops, "the target's position");
      expectMonotonic(offsets, "controller.offset");
      expect(trace.last.centerError, isNotNull);
      expect(trace.last.centerError!.abs(), lessThan(2),
          reason: "ends centered");
      expect(highlightedRows(tester), {target});
      await finish(tester);
    });

    test("$layout: a reply that grows after the jump ends fully shown",
        (tester) async {
      await pumpChat(tester, options, custom: layout == "Custom-mix");
      final target = nearTarget(tester);
      final targetN = int.parse(target.substring(2));
      view(tester).jumpToEvent(target);
      await record(tester, target, "grow-$layout", frames: 32);

      final heightBefore = rowRect(tester, target)!.height;
      final offsetBefore = view(tester).controller.offset;
      await deliver(tester, growEdit(target, 1, targetN));
      final trace =
          await record(tester, target, "grow-$layout", frames: 90, start: 512);
      final heightAfter = rowRect(tester, target)!.height;
      final offsetAfter = view(tester).controller.offset;
      final viewHeight = scrollViewport(tester)!.height;
      final correction = offsetAfter - offsetBefore;
      await snap?.call(tester, "grow-$layout-final");
      // ignore: avoid_print
      print("@@RUN grow-$layout height $heightBefore -> $heightAfter, "
          "offset $offsetBefore -> $offsetAfter (correction $correction), "
          "viewport $viewHeight");

      expect(heightAfter, greaterThan(heightBefore + 100),
          reason: "the row grew");
      expect(trace.last.top, isNotNull);
      expectFullyShown(rowRect(tester, target)!, scrollViewport(tester)!);
      await finish(tester);
    });
  }

  test("a far reply is centered once the list is visible again",
      (tester) async {
    await pumpChat(tester, LayoutOptions.discord);
    final target = farTarget(tester);

    view(tester).jumpToEvent(target);
    final trace = await record(tester, target, "far", snapOpaque: true);

    // Every frame the user can see the target in, it's already centered.
    for (final f in trace) {
      if (f.centerError == null || f.opacity < .99) continue;
      expect(f.centerError!.abs(), lessThan(2),
          reason: "visible off-center at ${f.ms} ms: $f");
    }
    expect(trace.last.opacity, 1);
    expect(trace.last.centerError, isNotNull);
    expect(highlightedRows(tester), {target});
    await finish(tester);
  });

  test("a reply far back in the history loads around it, centered once shown",
      (tester) async {
    await pumpChat(tester, LayoutOptions.discord);
    const target = r"$old20";
    bool loaded() =>
        view(tester).timeline.events.any((e) => e.eventId == target);
    expect(loaded(), isFalse, reason: "not loaded: the jump needs /context");
    final contextRequests = <String>[];
    final before = [for (var i = 19; i >= 0; i--) oldMessage(i).toJson()];
    final after = [for (var i = 21; i <= 40; i++) oldMessage(i).toJson()];
    contextResponse = (id) {
      contextRequests.add(id);
      if (id != target) return null;
      return {
        "event": oldMessage(20).toJson(),
        // Newest first, as the spec orders events_before.
        "events_before": before,
        "events_after": after,
        "start": "before-old",
        "end": "after-old",
        "state": [],
      };
    };

    view(tester).jumpToEvent(target);
    final trace = await record(tester, target, "context",
        frames: 120, snapOpaque: true, realWait: true);

    expect(contextRequests, contains(target));
    expect(loaded(), isTrue, reason: "swapped for the timeline around it");
    // Every frame the user can see the target in, it's already centered.
    for (final f in trace) {
      if (f.centerError == null || f.opacity < .99) continue;
      expect(f.centerError!.abs(), lessThan(2),
          reason: "visible off-center at ${f.ms} ms: $f");
    }
    expect(trace.last.opacity, 1, reason: "the list is visible again");
    expect(trace.last.centerError, isNotNull, reason: "the target is shown");
    expect(highlightedRows(tester), {target});
    await finish(tester);
  });

  for (final (phase, far, delay) in [
    ("the scroll", false, 200),
    ("the fade", true, 64),
  ]) {
    test("a message arriving during $phase highlights the target",
        (tester) async {
      await pumpChat(tester, LayoutOptions.discord);
      final id = far ? farTarget(tester) : nearTarget(tester);
      view(tester).jumpToEvent(id);
      for (var ms = 0; ms < delay; ms += 16) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      // ignore: avoid_print
      print("@@RUN insert-$delay at ${view(tester).controller.offset}");
      await deliver(tester, message(r"$new", 100));
      expect(view(tester).eventKeys.first.$2, r"$new");
      await record(tester, id, "insert-$delay", frames: 70);

      expect(highlightedRows(tester), {id});
      final highlighted = view(tester).highlightedEventState;
      expect(highlighted, isNotNull);
      expect(highlighted, same(keyOf(tester, id)!.currentState));
      await finish(tester);
    });
  }
}
