import 'package:commet/client/components/room_call/room_call_component.dart';
import 'package:commet/ui/molecules/room_call_button.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  RoomCallButtonState state(
          {bool inCall = false,
          bool encryptedOff = false,
          bool canJoin = true,
          int people = 0}) =>
      RoomCallButtonState.of(
          inCallHere: inCall,
          encryptedCallsOff: encryptedOff,
          canJoin: canJoin,
          participants: people);

  test('start, join, in call', () {
    expect(state(), RoomCallButtonState.start);
    expect(state(people: 3), RoomCallButtonState.join);
    expect(state(people: 3, inCall: true), RoomCallButtonState.inCall);
  });

  test('blocked: grey lock, the encrypted-room reason first', () {
    expect(state(canJoin: false), RoomCallButtonState.locked);
    expect(state(canJoin: false, people: 2), RoomCallButtonState.locked);
    expect(state(encryptedOff: true), RoomCallButtonState.needsEncryptedCalls);
    expect(state(encryptedOff: true, canJoin: false),
        RoomCallButtonState.needsEncryptedCalls);
  });

  test('being in the call wins over everything', () {
    expect(state(inCall: true, canJoin: false, encryptedOff: true),
        RoomCallButtonState.inCall);
  });

  test('tooltips', () {
    expect(RoomCallButtonState.join.tooltip(1), "Join call · 1 person");
    expect(RoomCallButtonState.join.tooltip(3), "Join call · 3 people");
    expect(
        RoomCallButtonState.locked.tooltip(0), "You can't call in this room");
  });

  test('permissions', () {
    const member = RoomCallPermissions(
        requiredLevel: 50,
        ownLevel: 0,
        canChangePermissions: false,
        othersBlocked: true);
    expect(member.canJoin, isFalse);
    expect(RoomCallPermissions.levelName(50), "moderators (power level 50)");
    expect(RoomCallPermissions.levelName(100), "admins (power level 100)");
    expect(RoomCallPermissions.levelName(10), "power level 10");
  });
}
