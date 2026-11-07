import 'package:commet/client/client.dart';
import 'package:commet/client/matrix/matrix_default_push_rule.dart';
import 'package:commet/ui/organisms/notification_level/apply_push_rule.dart';
import 'package:flutter_test/flutter_test.dart';

// Vommet issue 631: setting a notification level on many rooms at once, and
// rooms joined in a space following the space's level.
void main() {
  BulkPushRuleSkip? skip(
          {bool isDirect = false,
          bool isSpace = false,
          PushRule current = PushRule.notify,
          PushRule target = PushRule.mentionsOnly}) =>
      BulkPushRulePlan.skipFor(
          isDirect: isDirect,
          isSpace: isSpace,
          current: current,
          target: target);

  group("bulk change", () {
    test("changes an ordinary group room", () {
      expect(skip(), isNull);
      expect(skip(current: PushRule.mentionsOnly, target: PushRule.notify),
          isNull);
    });

    test("leaves direct messages and spaces alone", () {
      expect(skip(isDirect: true), BulkPushRuleSkip.direct);
      expect(skip(isSpace: true), BulkPushRuleSkip.space);
    });

    test("keeps muted rooms muted", () {
      expect(skip(current: PushRule.dontNotify), BulkPushRuleSkip.muted);
      expect(skip(current: PushRule.dontNotify, target: PushRule.notify),
          BulkPushRuleSkip.muted);
    });

    test("counts rooms already at the level, also when muting", () {
      expect(skip(current: PushRule.mentionsOnly), BulkPushRuleSkip.already);
      expect(skip(current: PushRule.dontNotify, target: PushRule.dontNotify),
          BulkPushRuleSkip.already);
      expect(skip(target: PushRule.dontNotify), isNull);
    });
  });

  group("space level for newly joined rooms", () {
    test("no space level means the default applies", () {
      expect(MatrixDefaultPushRule.inheritedLevel([]), isNull);
    });

    test("one space's level is used", () {
      expect(MatrixDefaultPushRule.inheritedLevel([PushRule.dontNotify]),
          PushRule.dontNotify);
    });

    test("the loudest of several spaces wins", () {
      expect(
          MatrixDefaultPushRule.inheritedLevel(
              [PushRule.dontNotify, PushRule.mentionsOnly]),
          PushRule.mentionsOnly);
      expect(
          MatrixDefaultPushRule.inheritedLevel(
              [PushRule.mentionsOnly, PushRule.notify, PushRule.dontNotify]),
          PushRule.notify);
    });
  });
}
