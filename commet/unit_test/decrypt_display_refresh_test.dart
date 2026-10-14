// #16: a message decrypted in place kept showing "Failed to decrypt" until the
// room was reopened, because its body was only rebuilt when the display id
// changed, and decrypting doesn't change it.

import 'package:commet/ui/molecules/timeline_events/events/timeline_event_view_message.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test("a decrypted message replaces the decryption error", () {
    expect(rebuildContent(displayIdChanged: false, showingDecryptError: true),
        isTrue);
  });

  test("an unchanged message isn't rebuilt", () {
    expect(rebuildContent(displayIdChanged: false, showingDecryptError: false),
        isFalse);
  });

  test("a changed display id (e.g. an edit) still rebuilds", () {
    expect(rebuildContent(displayIdChanged: true, showingDecryptError: false),
        isTrue);
  });
}
