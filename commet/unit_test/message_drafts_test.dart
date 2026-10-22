import 'package:commet/utils/message_drafts.dart';
import 'package:test/test.dart';

enum _Relation { reply }

void main() {
  test("a draft is kept per room", () {
    final drafts = MessageDrafts<String>();
    final a = MessageDrafts.keyFor("client", "!a:example.org");
    final b = MessageDrafts.keyFor("client", "!b:example.org");

    drafts.set(a, const MessageDraft("hello"));

    expect(drafts.get(a)?.text, "hello");
    expect(drafts.get(b), isNull);
  });

  test("threads, rooms and accounts have separate drafts", () {
    final room = MessageDrafts.keyFor("client", "!a:example.org");
    final thread =
        MessageDrafts.keyFor("client", "!a:example.org", threadId: r"$root");
    final otherAccount = MessageDrafts.keyFor("other", "!a:example.org");

    expect({room, thread, otherAccount}, hasLength(3));
  });

  test("blank text forgets the draft", () {
    final drafts = MessageDrafts<String>();
    final key = MessageDrafts.keyFor("client", "!a:example.org");

    drafts.set(key, const MessageDraft("hello"));
    drafts.set(key, const MessageDraft("   "));

    expect(drafts.get(key), isNull);
  });

  test("the reply target is kept with the text", () {
    final drafts = MessageDrafts<String>();
    final key = MessageDrafts.keyFor("client", "!a:example.org");

    drafts.set(
        key,
        const MessageDraft("answer",
            relatedEvent: r"$event", relation: _Relation.reply));

    expect(drafts.get(key)?.relatedEvent, r"$event");
    expect(drafts.get(key)?.relation, _Relation.reply);
  });

  test("clear removes the draft", () {
    final drafts = MessageDrafts<String>();
    final key = MessageDrafts.keyFor("client", "!a:example.org");

    drafts.set(key, const MessageDraft("hello"));
    drafts.clear(key);

    expect(drafts.get(key), isNull);
  });
}
