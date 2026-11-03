// Vommet: a direct invite to a room says whether its history goes along, and
// offers to keep it back only when it would actually be shared (Vommet issue
// 437).
import 'package:commet/ui/organisms/invitation_view/direct_invite_dialog.dart';
import 'package:commet/utils/space_hierarchy/invite_plan.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the share tick box only shows when history would be shared', () {
    expect(DirectInviteDialog.offersShareChoice(InviteHistory.included), true);
    for (final h in InviteHistory.values) {
      if (h == InviteHistory.included) continue;
      expect(DirectInviteDialog.offersShareChoice(h), false, reason: '$h');
    }
  });

  test('rooms whose history stays behind say why', () {
    expect(DirectInviteDialog.noteFor(InviteHistory.newMessagesOnly),
        DirectInviteDialog.directInviteNewMessagesOnlyNote);
    expect(DirectInviteDialog.noteFor(InviteHistory.notEncrypted),
        DirectInviteDialog.directInviteNotEncryptedNote);
    expect(DirectInviteDialog.noteFor(InviteHistory.included), isNull);
  });
}
