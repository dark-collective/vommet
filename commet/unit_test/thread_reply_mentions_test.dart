// Vommet issue 826: a reply in a thread lights the @ button only when its
// text names me, not because it answers my message.
import 'package:commet/utils/thread_reply_mentions.dart';
import 'package:flutter_test/flutter_test.dart';

const me = "@me:example.org";

bool check({
  bool highlight = true,
  String? body,
  String? html,
  List<String>? ids,
  String? name = "Mia",
}) =>
    threadReplyNamesMe(
      highlight: highlight,
      me: me,
      displayName: name,
      body: body,
      formattedBody: html,
      mentionUserIds: ids,
    );

void main() {
  test("no highlight is never a mention", () {
    expect(check(highlight: false, body: "Mia look", ids: [me]), isFalse);
  });

  test("m.mentions naming me without the text naming me is not a mention", () {
    expect(check(body: "sounds good", ids: [me]), isFalse);
  });

  test("a pill to me counts", () {
    expect(
      check(
        body: "Mia: look",
        html: '<a href="https://matrix.to/#/@me:example.org">Mia</a>: look',
        ids: [me],
      ),
      isTrue,
    );
  });

  test("an URL-encoded pill counts", () {
    expect(
      check(
        body: "hey",
        html: '<a href="https://matrix.to/#/%40me%3Aexample.org">x</a>',
        ids: [me],
      ),
      isTrue,
    );
  });

  test("my display name as a word counts, case-insensitive", () {
    expect(check(body: "thanks mia!"), isTrue);
    expect(check(body: "the miami trip", ids: [me]), isFalse);
  });

  test("me only inside the reply fallback quote is not a mention", () {
    expect(check(body: "> <@me:example.org> my question\n\nyes"), isFalse);
    expect(
      check(
        body: "yes",
        html: "<mx-reply><blockquote>@me:example.org said hi"
            "</blockquote></mx-reply>yes",
      ),
      isFalse,
    );
  });

  test("keyword and @room highlights still count", () {
    expect(check(body: "the deploy is done"), isTrue);
    expect(check(body: "everyone look", ids: []), isTrue);
  });
}
