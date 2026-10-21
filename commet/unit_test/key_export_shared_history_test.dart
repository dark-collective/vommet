import 'package:commet/client/matrix/key_export/matrix_key_export.dart';
import 'package:flutter_test/flutter_test.dart';

// Vommet issues 441, 519: released matrix-rust-sdk (Element) reads the
// unstable MSC4268 name, and rejects a key that carries two of the names.
void main() {
  const names = [
    "shared_history",
    "m.shared_history",
    "org.matrix.msc3061.shared_history",
  ];

  test('the flag is exported under exactly one name', () {
    for (final shared in [true, false]) {
      final fields = MatrixKeyExport.sharedHistoryFields(shared);
      expect(fields, {"org.matrix.msc3061.shared_history": shared});
      expect(fields.keys.where(names.contains), hasLength(1));
      expect(MatrixKeyExport.isSharedHistory(fields), shared);
    }
  });

  test('import reads any of the names', () {
    for (final name in names) {
      expect(MatrixKeyExport.isSharedHistory({name: true}), isTrue,
          reason: name);
    }
    expect(MatrixKeyExport.isSharedHistory({"shared_history": false}), isFalse);
    expect(MatrixKeyExport.isSharedHistory({}), isFalse);
  });
}
