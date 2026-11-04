import 'package:commet/ui/molecules/composer_formatting/format_actions.dart';
import 'package:commet/utils/underline_markdown.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// `[` and `]` mark the selection, `|` a collapsed cursor.
TextEditingValue v(String marked) {
  var cursor = marked.indexOf('|');
  if (cursor != -1) {
    return TextEditingValue(
        text: marked.replaceFirst('|', ''),
        selection: TextSelection.collapsed(offset: cursor));
  }
  var start = marked.indexOf('[');
  var end = marked.indexOf(']') - 1;
  return TextEditingValue(
      text: marked.replaceFirst('[', '').replaceFirst(']', ''),
      selection: TextSelection(baseOffset: start, extentOffset: end));
}

String show(TextEditingValue value) {
  var s = value.selection;
  if (s.isCollapsed) return value.text.replaceRange(s.start, s.start, '|');
  return value.text
      .replaceRange(s.end, s.end, ']')
      .replaceRange(s.start, s.start, '[');
}

void main() {
  group('toggleFormat', () {
    final cases = [
      ('wrap bold', '[word]', ComposerFormat.bold, '**[word]**'),
      ('unwrap bold', '**[word]**', ComposerFormat.bold, '[word]'),
      (
        'unwrap bold, selected markers',
        '[**word**]',
        ComposerFormat.bold,
        '[word]'
      ),
      ('italic', 'a [b] c', ComposerFormat.italic, 'a *[b]* c'),
      ('italic inside bold', '**[b]**', ComposerFormat.italic, '***[b]***'),
      (
        'remove italic from bold italic',
        '***[b]***',
        ComposerFormat.italic,
        '**[b]**'
      ),
      (
        'remove bold from bold italic',
        '***[b]***',
        ComposerFormat.bold,
        '*[b]*'
      ),
      (
        'bold does not unwrap italic',
        '*[b]*',
        ComposerFormat.bold,
        '***[b]***'
      ),
      ('underline', '[x]', ComposerFormat.underline, '__[x]__'),
      ('strike', '[x]', ComposerFormat.strike, '~~[x]~~'),
      ('spoiler', '[x]', ComposerFormat.spoiler, '||[x]||'),
      ('code', '[x]', ComposerFormat.code, '`[x]`'),
      (
        'trailing space left outside',
        '[word ]next',
        ComposerFormat.bold,
        '**[word]** next'
      ),
      ('cursor inserts a pair', 'a |', ComposerFormat.bold, 'a **|**'),
      ('cursor removes an empty pair', 'a **|**', ComposerFormat.bold, 'a |'),
      (
        'quote a line',
        'hello [there]',
        ComposerFormat.quote,
        '[> hello there]'
      ),
      (
        'quote several lines',
        '[one\ntwo]',
        ComposerFormat.quote,
        '[> one\n> two]'
      ),
      ('unquote', '[> one\n> two]', ComposerFormat.quote, '[one\ntwo]'),
      ('quote at cursor', 'ab|c', ComposerFormat.quote, '> ab|c'),
      (
        'multi-line code is a block',
        '[a\nb]',
        ComposerFormat.code,
        '```\n[a\nb]\n```'
      ),
    ];

    for (final (name, input, format, expected) in cases) {
      test(name, () {
        expect(show(toggleFormat(v(input), format)), expected);
      });
    }

    test('pressing twice restores the text', () {
      for (final f in [
        ComposerFormat.bold,
        ComposerFormat.italic,
        ComposerFormat.underline,
        ComposerFormat.strike,
        ComposerFormat.spoiler,
        ComposerFormat.code,
        ComposerFormat.quote,
      ]) {
        final start = v('say [hello] now');
        final twice = toggleFormat(toggleFormat(start, f), f);
        expect(twice.text, start.text, reason: f.name);
      }
    });
  });

  group('isFormatActive', () {
    test('bold', () {
      expect(isFormatActive(v('**[b]**'), ComposerFormat.bold), isTrue);
      expect(isFormatActive(v('*[b]*'), ComposerFormat.bold), isFalse);
      expect(isFormatActive(v('*[b]*'), ComposerFormat.italic), isTrue);
      expect(isFormatActive(v('**[b]**'), ComposerFormat.italic), isFalse);
      expect(isFormatActive(v('***[b]***'), ComposerFormat.italic), isTrue);
    });
    test('quote', () {
      expect(isFormatActive(v('> [a]'), ComposerFormat.quote), isTrue);
      expect(isFormatActive(v('[a]'), ComposerFormat.quote), isFalse);
    });
  });

  group('links', () {
    test('insertLink', () {
      expect(show(insertLink(v('see [here]'), 'here', 'https://a.example/x')),
          'see [here](https://a.example/x)|');
    });
    test('escapes brackets and parentheses', () {
      expect(insertLink(v('|'), 'a]b', 'https://x.example/(y)').text,
          '[a\\]b](https://x.example/(y%29)');
    });
    test('pasting a URL over a selection makes a link', () {
      final before = v('read [the guide] first');
      const after = TextEditingValue(
          text: 'read https://g.example/guide first',
          selection: TextSelection.collapsed(offset: 28));
      expect(show(linkFromPaste(before, after)!),
          'read [the guide](https://g.example/guide)| first');
    });
    test('pasting plain text is left alone', () {
      final before = v('read [the guide] first');
      const after = TextEditingValue(
          text: 'read words first',
          selection: TextSelection.collapsed(offset: 10));
      expect(linkFromPaste(before, after), isNull);
    });
    test('typing over a selection is left alone', () {
      final before = v('[x]');
      const after = TextEditingValue(
          text: 'h', selection: TextSelection.collapsed(offset: 1));
      expect(linkFromPaste(before, after), isNull);
    });
  });

  group('underline', () {
    test('markers become <u> after markdown', () {
      expect(underlineMarkersToHtml(underlineToMarkers('a __b c__ d')),
          'a <u>b c</u> d');
    });
    test('left alone', () {
      for (final s in [
        'snake__case__name',
        '__ spaced __',
        '`__code__`',
        '```\n__x__\n```',
        'no underline',
      ]) {
        expect(underlineToMarkers(s), s, reason: s);
      }
    });
  });
}
