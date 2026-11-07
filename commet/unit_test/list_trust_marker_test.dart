import 'package:commet/ui/atoms/encryption_marker.dart';
import 'package:commet/ui/atoms/list_trust_marker.dart';
import 'package:commet/ui/atoms/room_panel_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Vommet issue 131: chat lists flag only an unencrypted DM (amber) and an
// identity change (red); the icon sits right after the name, even when the
// name is too long and gets cut.
void main() {
  test("lists show only the unencrypted-DM and identity-changed markers", () {
    expect(ListTrustMarker.shownKind(EncryptionMarkerKind.notEncryptedDirect),
        EncryptionMarkerKind.notEncryptedDirect);
    expect(
        ListTrustMarker.shownKind(EncryptionMarkerKind.identityChangedDirect),
        EncryptionMarkerKind.identityChangedDirect);
    expect(
        ListTrustMarker.shownKind(EncryptionMarkerKind.verifiedDirect), isNull);
    expect(
        ListTrustMarker.shownKind(EncryptionMarkerKind.notEncrypted), isNull);
    expect(ListTrustMarker.shownKind(EncryptionMarkerKind.none), isNull);
  });

  testWidgets("the marker follows the name and stays visible when it's cut",
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(260, 200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: RoomPanelView(
          displayName:
              "Discord: someone with a really long display name that never ends",
          nameTrailing: Icon(Icons.no_encryption_outlined,
              key: ValueKey("marker"), size: 14),
        ),
      ),
    ));

    final marker = find.byKey(const ValueKey("marker"));
    expect(marker, findsOneWidget);
    expect(tester.takeException(), isNull);
    final right = tester.getRect(marker).right;
    expect(right, lessThanOrEqualTo(260));
  });
}
