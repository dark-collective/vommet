import 'package:commet/client/matrix/components/threads/thread_file_relation.dart';
import 'package:test/test.dart';

void main() {
  // Vommet issue 301: the upload placeholder must already be a thread reply,
  // with the relation the SDK gives the sent file.
  group("threadFileRelation", () {
    test("a file in a thread falls back to the thread's latest reply", () {
      expect(threadFileRelation(r"$root", r"$latest"), {
        "event_id": r"$root",
        "rel_type": "m.thread",
        "is_falling_back": true,
        "m.in_reply_to": {"event_id": r"$latest"},
      });
    });

    test("without a latest reply there is no reply fallback", () {
      expect(threadFileRelation(r"$root", null), {
        "event_id": r"$root",
        "rel_type": "m.thread",
        "is_falling_back": true,
      });
    });
  });
}
