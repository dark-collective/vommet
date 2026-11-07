// Vommet issue 1098: the real room-call invite reports failure to the card,
// while its existing acceptCall API keeps logging for notification callers.
import 'package:commet/client/components/voip/voip_session.dart';
import 'package:commet/client/matrix/components/room_call/matrix_room_call_invite.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/incoming_call_fixtures.dart';

void main() {
  for (final fails in [false, true]) {
    test('incoming invite reports ${fails ? "thrown" : "null"} join failure',
        () async {
      final component = AlertRoomCallComponent();
      if (fails) component.failure = StateError('join failed');
      final invite = MatrixRoomCallInvite(component,
          eventId: 'ring',
          callerId: '@alex:example.org',
          ring: const Duration(seconds: 30));
      await expectLater(invite.acceptCallWithResult(), throwsStateError);
      expect(invite.state, VoipState.ended);
      expect(component.changes.hasListener, isFalse);
      await component.changes.close();
    });
  }
  test('accepted invite joins and cancels its ring expiry', () async {
    final component = AlertRoomCallComponent()
      ..result = AlertCall(AlertClient('@lee:example.org'),
          state: VoipState.connected);
    final invite = MatrixRoomCallInvite(component,
        eventId: 'ring',
        callerId: '@alex:example.org',
        ring: const Duration(seconds: 30));
    expect(await invite.acceptCallWithResult(), same(component.result));
    expect(invite.state, VoipState.ended);
    expect(component.changes.hasListener, isFalse);
    await component.changes.close();
  });
}
