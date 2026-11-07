import 'package:commet/client/matrix/timeline_events/matrix_timeline_event_membership.dart';
import 'package:test/test.dart';

String classify(Map<String, dynamic>? prev, Map<String, dynamic> curr,
        {String sender = "@grin:example.org"}) =>
    MatrixTimelineEventMembership.classifyForTest(
        "@grin:example.org", sender, prev, curr);

void main() {
  test("first join is a join", () {
    expect(classify(null, {"membership": "join"}), "join");
  });

  test("rejoin after leaving is a join", () {
    expect(classify({"membership": "leave"}, {"membership": "join"}), "join");
  });

  test("display name change is not a join", () {
    expect(
        classify({"membership": "join", "displayname": "grin"},
            {"membership": "join", "displayname": "grin2"}),
        "updateDisplayName");
  });

  test("avatar change is not a join", () {
    expect(
        classify({"membership": "join", "avatar_url": "mxc://a/1"},
            {"membership": "join", "avatar_url": "mxc://a/2"}),
        "updateAvatar");
  });

  test("join -> join with no visible change is not a join", () {
    expect(
        classify({
          "membership": "join",
          "displayname": "grin"
        }, {
          "membership": "join",
          "displayname": "grin",
          "join_authorised_via_users_server": "@mod:example.org"
        }),
        "updateProfile");
  });
}
