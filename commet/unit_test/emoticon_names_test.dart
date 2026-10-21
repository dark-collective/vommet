import 'package:commet/utils/emoticon_names.dart';
import 'package:test/test.dart';

void main() {
  group('EmoticonNames.unique', () {
    test('keeps a free name', () {
      expect(EmoticonNames.unique('cat', ['dog']), 'cat');
    });

    test('suffixes a taken name', () {
      expect(EmoticonNames.unique('cat', ['cat']), 'cat_2');
    });

    test('skips taken suffixes', () {
      expect(EmoticonNames.unique('cat', ['cat', 'cat_2', 'cat_3']), 'cat_4');
    });
  });

  group('EmoticonNames.uniqueAll', () {
    test('avoids existing names and duplicates within the batch', () {
      expect(
          EmoticonNames.uniqueAll(['cat', 'cat', 'dog', 'fox'], ['cat', 'fox']),
          ['cat_2', 'cat_3', 'dog', 'fox_2']);
    });

    test('empty batch', () {
      expect(EmoticonNames.uniqueAll([], ['cat']), isEmpty);
    });
  });
}
