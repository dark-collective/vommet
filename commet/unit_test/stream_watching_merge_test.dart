import 'package:commet/client/matrix/components/voip_room/vommet_stream_watching.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Set<String> merge(String? attribute, String? data) =>
      LivekitStreamWatching.mergeWatching(attribute, data);

  test("attribute alone", () {
    expect(merge('["@a:x"]', null), {"@a:x"});
  });

  test("data message alone, when the attribute was rejected", () {
    expect(merge(null, '["@a:x","@b:x"]'), {"@a:x", "@b:x"});
    expect(merge("", '["@a:x"]'), {"@a:x"});
  });

  test("both sources together, without duplicates", () {
    expect(merge('["@a:x"]', '["@a:x","@b:x"]'), {"@a:x", "@b:x"});
  });

  test("nothing watched or hidden", () {
    expect(merge(null, null), isEmpty);
    expect(merge("", "[]"), isEmpty);
  });

  test("garbage is ignored", () {
    expect(merge("not json", '{"a":1}'), isEmpty);
    expect(merge('["@a:x", 3]', "["), {"@a:x"});
  });

  group("use data messages (Vommet issue 871)", () {
    bool use({bool grant = true, bool denied = false, bool timedOut = false}) =>
        LivekitStreamWatching.useDataMessages(
            canUpdateMetadata: grant, denied: denied, timedOut: timedOut);

    test("no canUpdateMetadata grant", () => expect(use(grant: false), true));
    test("attribute refused", () => expect(use(denied: true), true));
    test("SFU never answered", () => expect(use(timedOut: true), true));
    test("granted and answered: attribute only", () => expect(use(), false));
  });

  group("data message targets (Vommet issue 871)", () {
    ({bool send, List<String>? to}) targets(String value,
            {String? last,
            bool sameRoom = true,
            Set<String> peers = const {"a", "b"},
            Set<String> lastPeers = const {"a", "b"}}) =>
        LivekitStreamWatching.dataTargets(
            value: value,
            lastValue: last,
            sameRoom: sameRoom,
            peers: peers,
            lastPeers: lastPeers);
    const w = '["@s:x"]';

    test("value changed: everyone", () {
      expect(targets(w, last: ""), (send: true, to: null));
      expect(targets("", last: w), (send: true, to: null));
      expect(targets(w), (send: true, to: null));
    });

    test("moved to another SFU: everyone", () {
      expect(targets(w, last: w, sameRoom: false), (send: true, to: null));
    });

    test("same value, new peer: only the newcomer", () {
      final t = targets(w, last: w, peers: {"a", "b", "c"});
      expect(t.send, true);
      expect(t.to, ["c"]);
    });

    test("same value, nobody new: nothing", () {
      expect(targets(w, last: w, peers: {"a"}), (send: false, to: null));
    });

    test("empty value, newcomer: nothing", () {
      expect(targets("", last: "", peers: {"a", "b", "c"}),
          (send: false, to: null));
    });

    test("first call with nothing watched: nothing", () {
      expect(targets(""), (send: false, to: null));
      expect(targets("", last: w, sameRoom: false), (send: false, to: null));
    });
  });
}
