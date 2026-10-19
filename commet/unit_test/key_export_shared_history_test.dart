import 'package:commet/client/matrix/key_export/matrix_key_export.dart';
import 'package:flutter_test/flutter_test.dart';

// Vommet issue 441: released matrix-rust-sdk (Element) only reads the
// prefixed MSC4268 names, so exported keys carry all of them.
void main() {
  test('a shareable key is exported under every name', () {
    expect(MatrixKeyExport.sharedHistoryFields(true), {
      "shared_history": true,
      "m.shared_history": true,
      "org.matrix.msc3061.shared_history": true,
    });
  });

  test('a key that is not shareable only carries the spec name', () {
    expect(
        MatrixKeyExport.sharedHistoryFields(false), {"shared_history": false});
  });

  test('import reads any of the names', () {
    for (final name in [
      "shared_history",
      "m.shared_history",
      "org.matrix.msc3061.shared_history",
    ]) {
      expect(MatrixKeyExport.isSharedHistory({name: true}), isTrue,
          reason: name);
    }
    expect(MatrixKeyExport.isSharedHistory({"shared_history": false}), isFalse);
    expect(MatrixKeyExport.isSharedHistory({}), isFalse);
  });
}
