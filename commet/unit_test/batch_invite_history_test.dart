import 'package:commet/ui/organisms/invitation_view/batch_invite_source.dart';
import 'package:commet/utils/invitations/invitation_batch.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a sent history result is success, not a nonempty-map failure', () {
    final i = BatchInviteItem(
      userId: 'a',
      roomId: 'r',
      roomName: 'Room',
      operation: InviteOperation.history,
    );
    ClientBatchInviteSource.recordHistoryResult(i, 'sent');
    expect(i.reason, contains('recorded'));
  });
  for (final outcome in ['no_cross_signed_devices', 'nothing_shareable']) {
    test('$outcome records the grant without claiming immediate delivery', () {
      final i = BatchInviteItem(
        userId: 'a',
        roomId: 'r',
        roomName: 'Room',
        operation: InviteOperation.history,
      );
      ClientBatchInviteSource.recordHistoryResult(i, outcome);
      expect(i.reason, isNotNull);
    });
  }
  for (final outcome in ['identity_changed', 'error']) {
    test('$outcome needs attention independently from the invitation', () {
      final i = BatchInviteItem(
        userId: 'a',
        roomId: 'r',
        roomName: 'Room',
        operation: InviteOperation.history,
      );
      expect(
        () => ClientBatchInviteSource.recordHistoryResult(i, outcome),
        throwsA(isA<HistoryShareNeedsAttention>()),
      );
    });
  }
}
