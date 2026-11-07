import 'package:commet/ui/organisms/room_side_panel/room_side_panel.dart';
import 'package:flutter_test/flutter_test.dart';

// Vommet issue 468: closing a thread must not reopen a closed right panel.
void main() {
  test("a thread opened from the thread list closes back to it", () {
    for (final hidden in [false, true]) {
      expect(
          RoomSidePanel.stateAfterThreadClosed(
              fromThreadsList: true, panelHidden: hidden),
          SidePanelState.threads);
    }
  });

  test("closing a thread with the panel open shows the member list", () {
    expect(
        RoomSidePanel.stateAfterThreadClosed(
            fromThreadsList: false, panelHidden: false),
        SidePanelState.defaultView);
  });

  test("closing a thread with the panel closed leaves it closed", () {
    expect(
        RoomSidePanel.stateAfterThreadClosed(
            fromThreadsList: false, panelHidden: true),
        SidePanelState.nothing);
  });
}
