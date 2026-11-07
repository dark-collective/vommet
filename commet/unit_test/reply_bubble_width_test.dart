// Vommet issue 1067: in the chat-bubble layout a bubble with a reply was
// much wider than its content. The real path: every reply the Matrix SDK
// sends carries `format: org.matrix.custom.html` (Room.sendEvent adds the
// mx-reply fallback), so its text renders through flutter_html, whose block
// <body> box takes all the width it gets. A plain "test" message renders as
// PlaintextMessageBody and stays snug.
//
// This pumps the real TimelineEventViewMessage, the widget the timeline
// builds for a message, with the bubble layout on. Fakes stand in only for
// the client, room and timeline lookups.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:commet/cache/file_provider.dart';
import 'package:commet/client/attachment.dart';
import 'package:commet/client/client.dart';
import 'package:commet/client/components/component.dart';
import 'package:commet/client/components/profile/profile_component.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/matrix_timeline.dart';
import 'package:commet/client/matrix/timeline_events/matrix_timeline_event_message.dart';
import 'package:commet/client/member.dart';
import 'package:commet/client/permissions.dart';
import 'package:commet/client/timeline_events/timeline_event.dart';
import 'package:commet/client/timeline_events/timeline_event_deleted.dart';
import 'package:commet/config/layout_style.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/atoms/reply_quote.dart';
import 'package:commet/ui/molecules/timeline_events/events/timeline_event_view_message.dart';
import 'package:commet/ui/molecules/timeline_events/events/timeline_event_view_reply.dart';
import 'package:commet/ui/molecules/timeline_events/layouts/timeline_event_layout_bubble.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_dark.dart';

const me = '@rowan:example.org';
const sam = '@sam:example.org';
const roomId = '!room:example.org';

class _SdkRoom extends Fake implements matrix.Room {
  @override
  String get id => roomId;
}

class _SdkTimeline extends Fake implements matrix.Timeline {
  @override
  final Map<String, Map<String, Set<matrix.Event>>> aggregatedEvents = {};
}

class _Self extends Fake implements Profile {
  @override
  String get identifier => me;
}

class _Client extends Fake implements Client {
  @override
  Profile? get self => _Self();
  @override
  String get identifier => 'client';
  @override
  T? getComponent<T extends Component>() => null;
}

class _Member extends Fake implements Member {
  _Member(this.identifier);
  @override
  final String identifier;
  @override
  String get displayName => identifier == me ? 'Rowan' : 'Sam';
  @override
  Color get defaultColor => const Color(0xffff7070);
  @override
  String get userName => identifier;
  @override
  String? get detail => null;
  @override
  String? get avatarId => null;
  @override
  ImageProvider? get avatar => null;
  @override
  ImageProvider? get largeAvatar => null;
}

class _Room extends Fake implements Room {
  @override
  String get identifier => roomId;
  @override
  Client get client => _Client();
  @override
  Member getMemberOrFallback(String id) => _Member(id);
  @override
  Permissions get permissions => _Permissions();
}

class _Permissions extends Permissions {}

final _room = _Room();

class _MatrixClient extends Fake implements MatrixClient {
  @override
  String get identifier => 'client';
  @override
  Room? getRoom(String identifier) => _room;
}

class _Timeline extends Fake implements MatrixTimeline {
  _Timeline(this.events);
  @override
  List<TimelineEvent> events;
  @override
  final matrix.Timeline matrixTimeline = _SdkTimeline();
  @override
  Room get room => _room;
  @override
  StreamController<int> onChange = StreamController.broadcast();
  @override
  TimelineEvent? tryGetEvent(String eventId) =>
      events.where((e) => e.eventId == eventId).firstOrNull;
  @override
  String getDisplayId(TimelineEvent event) => event.eventId;
  @override
  bool isEventRedacted(TimelineEvent event) => false;
  @override
  DeletedMessageInfo? deletedMessageInfo(TimelineEvent event) => null;
}

class _File extends Fake implements FileProvider {}

/// A 1×1 PNG: the picture's bytes don't matter, the quote's thumbnail is a
/// fixed 36 px square.
final _png = Uint8List.fromList(base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=='));

final _sdkRoom = _SdkRoom();
final _client = _MatrixClient();

/// Who sends the test's messages: you (own bubbles) or Sam.
String sender = me;

MatrixTimelineEventMessage _event(String id, Map<String, dynamic> content) =>
    MatrixTimelineEventMessage(
        matrix.Event(
          content: content,
          type: matrix.EventTypes.Message,
          eventId: id,
          senderId: sender,
          originServerTs: DateTime(2026, 11, 2, 7, 48),
          room: _sdkRoom,
        ),
        client: _client);

/// A plain message, as sent without formatting.
MatrixTimelineEventMessage plainMessage(String id, String body) =>
    _event(id, {'msgtype': 'm.text', 'body': body});

/// A picture, as MatrixTimelineEventMessage parses one, with the network
/// image swapped for a local one (the media download is the boundary).
MatrixTimelineEventMessage pictureMessage(String id) =>
    _event(id, {'msgtype': 'm.image', 'body': 'photo.jpg'})
      ..attachments = [
        ImageAttachment(MemoryImage(_png), _File(),
            name: 'photo.jpg', mimeType: 'image/png', width: 800, height: 600)
      ];

/// A reply to [quoted], with the content matrix-dart-sdk's Room.sendEvent
/// gives every reply: the mx-reply fallback in an HTML formatted body, the
/// quoted sender in m.mentions.
MatrixTimelineEventMessage replyMessage(
        String id, String body, MatrixTimelineEventMessage quoted) =>
    _event(id, {
      'msgtype': 'm.text',
      'body': '> <${quoted.senderId}> ${quoted.body}\n\n$body',
      'format': 'org.matrix.custom.html',
      'formatted_body': '<mx-reply><blockquote>'
          '<a href="https://matrix.to/#/$roomId/${quoted.eventId}">In reply to</a> '
          '<a href="https://matrix.to/#/${quoted.senderId}">${quoted.senderId}</a><br>${quoted.body}'
          '</blockquote></mx-reply>$body',
      'm.mentions': {
        'user_ids': [quoted.senderId]
      },
      'm.relates_to': {
        'm.in_reply_to': {'event_id': quoted.eventId}
      },
    });

/// The layout styles that draw bubbles (Discord style draws none):
/// Telegram style limits the width and keeps your bubbles on the right;
/// a Custom mix with bubbles on and the defaults otherwise.
enum BubbleStyle { telegram, custom }

/// Turns the bubble layout on with [style]'s settings, as Settings ›
/// Appearance › Layout does.
Future<void> applyStyle(BubbleStyle style) {
  const custom = LayoutOptions(
      oneChatList: true,
      captionBelow: false,
      limitWidth: false,
      bubbles: true,
      ownSide: OwnBubbleSide.rightWhenNarrow,
      avatarAtBottom: false);
  return style == BubbleStyle.telegram
      ? LayoutOptions.telegram.save()
      : custom.save();
}

/// The real message widget the timeline builds for the event at [index].
Widget bubbleFor(MatrixTimeline timeline, int index, {Key? key}) =>
    TimelineEventViewMessage(key: key, timeline: timeline, initialIndex: index);

/// The timeline width: own bubbles sit on the right (under 1000 px) and
/// the two styles' maximum widths differ (Telegram 640, Custom 675).
const timelineWidth = 900.0;

double maxBubbleWidth(BubbleStyle style) =>
    TimelineEventLayoutBubble.maxBubbleWidth(timelineWidth,
        limit: style == BubbleStyle.telegram
            ? LayoutOptions.maxMessageWidth
            : null);

/// Pumps a plain "test" message and a reply under it, like the issue's
/// screenshot, inside a RepaintBoundary keyed "timeline".
Future<void> pumpReply(WidgetTester tester,
    {required ReplyStyle replyStyle,
    required BubbleStyle style,
    required bool own,
    String quotedText = 'test',
    bool quotedPicture = false,
    String replyText = 'test'}) async {
  await preferences.replyStyle.set(replyStyle.name);
  await applyStyle(style);
  sender = own ? me : sam;
  tester.view.physicalSize = const Size(timelineWidth, 400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final quoted = quotedPicture
      ? pictureMessage('\$quoted')
      : plainMessage('\$quoted', quotedText);
  final reply = replyMessage('\$reply', replyText, quoted);
  // Newest first, as the timeline holds them.
  final timeline = _Timeline([reply, quoted]);
  await tester.pumpWidget(MaterialApp(
    theme: ThemeDark.theme,
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      body: RepaintBoundary(
        key: const ValueKey('timeline'),
        child: Material(
          color: ThemeDark.theme.colorScheme.surface,
          child: SizedBox(
            width: timelineWidth,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              bubbleFor(timeline, 1, key: const ValueKey('plain')),
              bubbleFor(timeline, 0, key: const ValueKey('reply')),
            ]),
          ),
        ),
      ),
    ),
  ));
  await tester.pump();
}

/// The bubble (the decorated box) of the message keyed [key].
Finder bubbleBox(String key) => find
    .descendant(
        of: find.byKey(ValueKey(key)),
        matching: find.byWidgetPredicate((w) =>
            w is Container &&
            w.padding == const EdgeInsets.fromLTRB(10, 6, 10, 6)))
    .first;

/// The widest piece of content in the bubble: its reply preview and every
/// line of text (the reply's text, the quote, the time).
double contentWidth(WidgetTester tester, String key) {
  var widest = 0.0;
  final reply = find.descendant(
      of: find.byKey(ValueKey(key)),
      matching: find.byType(TimelineEventViewReply));
  if (reply.evaluate().isNotEmpty) widest = tester.getSize(reply).width;
  for (final p in tester.renderObjectList<RenderParagraph>(
      find.descendant(of: bubbleBox(key), matching: find.byType(RichText)))) {
    if (p.size.width > widest) widest = p.size.width;
  }
  return widest;
}

/// A formatted (HTML) message, as Element or Vommet sends one.
MatrixTimelineEventMessage formattedMessage(String id, String html) =>
    _event(id, {
      'msgtype': 'm.text',
      'body': html.replaceAll(RegExp('<[^>]*>'), ' '),
      'format': 'org.matrix.custom.html',
      'formatted_body': html,
    });

const _longText = 'a long line of text that goes on and on ';
const _longUrl = 'https://example.org/'
    'aVeryLongUnbrokenPathThatHasNoSpacesAtAllAndKeepsGoingPastTheBubble'
    'aVeryLongUnbrokenPathThatHasNoSpacesAtAllAndKeepsGoingPastTheBubble';

/// How a formatted message's bubble may be sized.
enum Fit {
  /// As wide as its text (inline-only HTML).
  hug,

  /// The bubble maximum, as on base: long text wraps there, a code block
  /// scrolls there, and block HTML (quote, rule) keeps the full width.
  max,

  /// No width rule (an HTML table shows no cells in the app).
  any,
}

/// Formatted messages other than replies: key -> (formatted_body, fit).
/// flutter_html's shrink-wrap only sizes its root box, so only inline-only
/// HTML hugs; everything else must look as on base, without overflow.
final formattedCases = <String, (String, Fit)>{
  'paragraphs': ('<p>first</p><p>second</p>', Fit.hug),
  'inline': (
    '<b>bold</b>, <code>code</code> and <a href="https://example.org">a link</a>',
    Fit.hug
  ),
  'paragraphs-long': ('<p>${_longText * 6}</p><p>second</p>', Fit.max),
  'code-block-long': (
    '<pre><code>${'value = compute(1); ' * 20}</code></pre>',
    Fit.max
  ),
  'table': (
    '<table><tr><th>a</th><th>b</th></tr><tr><td>1</td><td>2</td></tr></table>',
    Fit.any
  ),
  'blockquote': ('<blockquote>quoted</blockquote><p>reply</p>', Fit.max),
  'blockquote-long': ('<blockquote>${_longText * 6}</blockquote>', Fit.max),
  'hr': ('<p>above</p><hr><p>below</p>', Fit.max),
  'long-url': ('<a href="$_longUrl">$_longUrl</a>', Fit.max),
};

/// Pumps every [formattedCases] message as its own bubble (keyed by its
/// case name) in a RepaintBoundary keyed "timeline".
Future<void> pumpFormatted(WidgetTester tester,
    {required BubbleStyle style, bool own = true}) async {
  tester.view.physicalSize = const Size(timelineWidth, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await applyStyle(style);
  sender = own ? me : sam;
  final keys = formattedCases.keys.toList();
  final timeline = _Timeline(
      [for (final k in keys) formattedMessage('\$$k', formattedCases[k]!.$1)]);
  await tester.pumpWidget(MaterialApp(
    theme: ThemeDark.theme,
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      body: SingleChildScrollView(
        child: RepaintBoundary(
          key: const ValueKey('timeline'),
          child: Material(
            color: ThemeDark.theme.colorScheme.surface,
            child: SizedBox(
              width: timelineWidth,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                for (var i = 0; i < keys.length; i++)
                  bubbleFor(timeline, i, key: ValueKey(keys[i])),
              ]),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.pump();
}

void main() {
  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
  });

  test('the SDK reply content takes the HTML path (as on device)', () {
    final quoted = plainMessage('\$quoted', 'test');
    final reply = replyMessage('\$reply', 'test', quoted);
    expect(
        MatrixTimelineEventMessage.usesFormattedBody(
            'm.text', reply.event.content, reply.event.formattedText),
        isTrue);
    expect(
        MatrixTimelineEventMessage.usesFormattedBody(
            'm.text', quoted.event.content, quoted.event.formattedText),
        isFalse);
  });

  group('a bubble with a reply fits its content (Vommet issue 1067)', () {
    for (final style in BubbleStyle.values) {
      for (final replyStyle in ReplyStyle.values) {
        for (final own in [true, false]) {
          final side = own ? 'own' : "others'";
          testWidgets(
              '${style.name} style, ${replyStyle.name} reply, $side: '
              'a short reply to a short message hugs its content',
              (tester) async {
            await pumpReply(tester,
                replyStyle: replyStyle, style: style, own: own);
            expect(tester.takeException(), isNull);
            final width = tester.getSize(bubbleBox('reply')).width;
            // 10 px padding on each side, plus a few px of the time row.
            expect(width, lessThanOrEqualTo(contentWidth(tester, 'reply') + 24),
                reason: 'reply bubble $width px wide, content '
                    '${contentWidth(tester, 'reply')} px');
            expect(width, lessThan(maxBubbleWidth(style) / 2));
            // The plain message above it stays snug too.
            expect(tester.getSize(bubbleBox('plain')).width,
                lessThanOrEqualTo(contentWidth(tester, 'plain') + 21));
            await tester.pumpWidget(const SizedBox());
          });
        }
      }

      for (final replyStyle in ReplyStyle.values) {
        for (final own in [true, false]) {
          final side = own ? 'own' : "others'";
          testWidgets(
              '${style.name} style, ${replyStyle.name} reply, $side: '
              'a short reply to a picture hugs its content', (tester) async {
            await pumpReply(tester,
                replyStyle: replyStyle,
                style: style,
                own: own,
                quotedPicture: true);
            expect(tester.takeException(), isNull);
            // Quote and card show the picture; compact names it.
            expect(find.byKey(const ValueKey('reply-quote-thumbnail')),
                replyStyle.inline ? findsOneWidget : findsNothing);
            final width = tester.getSize(bubbleBox('reply')).width;
            expect(width, lessThanOrEqualTo(contentWidth(tester, 'reply') + 24),
                reason: 'reply bubble $width px wide, content '
                    '${contentWidth(tester, 'reply')} px');
            expect(width, lessThan(maxBubbleWidth(style) / 2));
            await tester.pumpWidget(const SizedBox());
          });
        }
      }

      for (final own in [true, false]) {
        final side = own ? 'own' : "others'";
        testWidgets(
            '${style.name} style, $side: a long reply still wraps at the '
            'bubble maximum', (tester) async {
          await pumpReply(tester,
              replyStyle: ReplyStyle.quote,
              style: style,
              own: own,
              replyText: 'a long reply that goes on ' * 12);
          expect(tester.takeException(), isNull);
          expect(tester.getSize(bubbleBox('reply')).width,
              moreOrLessEquals(maxBubbleWidth(style), epsilon: 0.5));
          await tester.pumpWidget(const SizedBox());
        });

        // Accepted limit (operator, 11-04): a reply whose own text has block
        // HTML (here a quote) keeps the full bubble width, as on base.
        testWidgets(
            '${style.name} style, $side: a reply with a quote in its text '
            'keeps the bubble maximum', (tester) async {
          await pumpReply(tester,
              replyStyle: ReplyStyle.quote,
              style: style,
              own: own,
              replyText: '<blockquote>quoted</blockquote><p>reply</p>');
          expect(tester.takeException(), isNull);
          expect(tester.getSize(bubbleBox('reply')).width,
              moreOrLessEquals(maxBubbleWidth(style), epsilon: 1));
          await tester.pumpWidget(const SizedBox());
        });

        testWidgets(
            '${style.name} style, $side: a short reply to a long message '
            'is as wide as the quote', (tester) async {
          await pumpReply(tester,
              replyStyle: ReplyStyle.quote,
              style: style,
              own: own,
              quotedText: 'a long quoted message ' * 12);
          expect(tester.takeException(), isNull);
          final width = tester.getSize(bubbleBox('reply')).width;
          expect(width, lessThanOrEqualTo(contentWidth(tester, 'reply') + 24));
          expect(width, greaterThan(maxBubbleWidth(style) / 2));
          await tester.pumpWidget(const SizedBox());
        });
      }
    }
  });

  group('formatted messages in a bubble (Vommet issue 1067, shrink-wrap)', () {
    for (final style in BubbleStyle.values) {
      for (final own in [true, false]) {
        final side = own ? 'own' : "others'";
        for (final MapEntry(key: name, value: (_, fit))
            in formattedCases.entries) {
          testWidgets(
              '${style.name} style, $side: $name '
              '${switch (fit) {
                Fit.hug => 'hugs its content',
                Fit.max => 'keeps the bubble maximum',
                Fit.any => 'fits'
              }}', (tester) async {
            await pumpFormatted(tester, style: style, own: own);
            expect(tester.takeException(), isNull);
            final width = tester.getSize(bubbleBox(name)).width;
            final max = maxBubbleWidth(style);
            expect(width, lessThanOrEqualTo(max + 0.5));
            switch (fit) {
              case Fit.hug:
                expect(width, lessThan(max / 2));
              case Fit.max:
                expect(width, moreOrLessEquals(max, epsilon: 1));
              case Fit.any:
                break;
            }
            await tester.pumpWidget(const SizedBox());
          });
        }
      }
    }
  });
}
