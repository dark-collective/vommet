import 'package:commet/utils/dm_shape.dart';
import 'package:flutter_test/flutter_test.dart';

const me = "@me:example.org";
const juniper = "@juniper:example.org";
const kit = "@kit:example.org";

DmShape decide(
        {bool inMDirect = true,
        List<String> active = const [me, juniper],
        String? partner = juniper,
        String? membership = "join",
        int? count}) =>
    DmShape.decide(
        inMDirect: inMDirect,
        activeMemberIds: active,
        ownId: me,
        partnerId: partner,
        partnerMembership: membership,
        activeMemberCount: count);

void main() {
  group("DmShape.decide", () {
    test("a direct chat with one other person is a person", () {
      expect(decide(), const DmShape(DmShapeKind.person, partnerId: juniper));
    });

    test("an invited partner still counts", () {
      expect(decide(membership: "invite").kind, DmShapeKind.person);
    });

    test("only me left in it, partner gone: left partner", () {
      final shape = decide(active: const [me], membership: "leave");
      expect(shape.kind, DmShapeKind.leftPartner);
      expect(shape.partnerId, juniper);
      expect(shape.isPerson, isTrue);
      expect(shape.partnerLeft, isTrue);
    });

    test("a banned partner counts as left", () {
      expect(decide(active: const [me], membership: "ban").kind,
          DmShapeKind.leftPartner);
    });

    test("an unknown partner membership never counts as left", () {
      expect(decide(active: const [me], membership: null).kind,
          DmShapeKind.person);
    });

    test("three active people: a group that started as a direct chat", () {
      final shape = decide(active: const [me, juniper, kit]);
      expect(shape.kind, DmShapeKind.group);
      expect(shape.convertedFromDm, isTrue);
      expect(shape.partnerId, juniper);
      expect(shape.isPerson, isFalse);
    });

    test("an invited third person makes it a group", () {
      // kit is invited: active = joined + invited
      expect(decide(active: const [me, juniper, kit]).kind, DmShapeKind.group);
    });

    test("the server's member count wins over lazy-loaded members", () {
      expect(decide(count: 3).kind, DmShapeKind.group);
      expect(decide(count: 2).kind, DmShapeKind.person);
      // A stale lower count never hides members we can see.
      expect(decide(active: const [me, juniper, kit], count: 2).kind,
          DmShapeKind.group);
    });

    test("the third person leaving makes it a person again", () {
      expect(decide(active: const [me, juniper, kit]).isPerson, isFalse);
      expect(decide(active: const [me, juniper]).isPerson, isTrue);
    });

    test("partner left while someone else is still here", () {
      expect(decide(active: const [me, kit], membership: "leave").kind,
          DmShapeKind.leftPartner);
    });

    test("partner left and two others here: a group", () {
      expect(
          decide(
                  active: const [me, kit, "@ash:example.org"],
                  membership: "leave")
              .kind,
          DmShapeKind.group);
    });

    test("a two-person room not in m.direct is a group", () {
      final shape = decide(inMDirect: false);
      expect(shape, DmShape.room);
      expect(shape.convertedFromDm, isFalse);
      expect(shape.partnerId, isNull);
    });

    test("without a partner id the one other member is the partner", () {
      expect(decide(partner: null).partnerId, juniper);
      expect(decide(partner: null, active: const [me]).partnerId, isNull);
    });

    test("own id is counted even when missing from the members", () {
      expect(decide(active: const [juniper]).kind, DmShapeKind.person);
      expect(decide(active: const [juniper, kit]).kind, DmShapeKind.group);
    });
  });

  group("dmGroupName", () {
    test("names", () {
      expect(dmGroupName(const []), "");
      expect(dmGroupName(const ["Juniper"]), "Juniper");
      expect(dmGroupName(const ["Juniper", "Kit"]), "Juniper and Kit");
      expect(
          dmGroupName(const ["Juniper", "Kit", "Ash"]), "Juniper, Kit and Ash");
      expect(dmGroupName(const ["Juniper", "Kit", "Ash", "Rowan"]),
          "Juniper, Kit, Ash and 1 other");
      expect(dmGroupName(const ["Juniper", "Kit"], total: 5),
          "Juniper, Kit and 3 others");
    });
  });
}
