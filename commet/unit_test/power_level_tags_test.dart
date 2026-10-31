import 'package:commet/client/matrix/matrix_role.dart';
import 'package:commet/client/matrix/power_level_tags.dart';
import 'package:flutter/painting.dart';
import 'package:test/test.dart';

void main() {
  // Vommet issue 67: MSC3949 power level tags.
  final tags = PowerLevelTags.fromContent({
    "100": {"name": "Admin", "color": "#e5484d"},
    "50": {"name": "Moderator", "color": "#30a46c"},
    "38": {
      "name": "Bot",
      "icon": {"key": "🤖"}
    },
    "20": {
      "name": "Pictured",
      "icon": {"key": "mxc://example.org/abc"}
    },
    "x": {"name": "not a level"},
    "10": {"color": "#fff"},
  })!;

  test('parses tags, highest first, skipping bad entries', () {
    expect(tags.levels.map((e) => e.$1), [100, 50, 38, 20]);
    expect(tags.levels.first.$2.color, const Color(0xFFE5484D));
    expect(tags.tagFor(38)!.$2.emoji, "🤖");
    expect(tags.tagFor(20)!.$2.emoji, isNull);
  });

  test('levels without a tag use the nearest lower tag', () {
    expect(tags.tagFor(100)!.$2.name, "Admin");
    expect(tags.tagFor(75)!.$2.name, "Moderator");
    expect(tags.tagFor(40)!.$1, 38);
    expect(tags.tagFor(19), isNull);
  });

  test('colours', () {
    expect(PowerLevelTags.parseColor("#abc"), const Color(0xFFAABBCC));
    expect(PowerLevelTags.parseColor("red"), isNull);
    expect(PowerLevelTags.parseColor("#12345"), isNull);
  });

  test('nothing usable gives null', () {
    expect(PowerLevelTags.fromContent(null), isNull);
    expect(PowerLevelTags.fromContent({"5": "x"}), isNull);
  });

  test('roles take the tag, and group by tagged level', () {
    final bot = MatrixRole(40, tags: tags);
    expect(bot.name, "Bot");
    expect(bot.emoji, "🤖");
    expect(bot.rank, 38);
    expect(MatrixRole(45, tags: tags), bot);
    expect(MatrixRole(45, tags: tags).hashCode, bot.hashCode);

    final untagged = MatrixRole(10, tags: tags);
    expect(untagged.name, "Member");
    expect(untagged.rank, 0);
    expect(untagged.color, isNull);
  });

  test('a lower tag does not replace a higher built-in role', () {
    final onlyHelper = PowerLevelTags.fromContent({
      "10": {"name": "Helper"},
      "-1": {"name": "Muted"},
    })!;
    final admin = MatrixRole(100, tags: onlyHelper);
    expect(admin.name, "Admin");
    expect(admin.rank, 100);
    expect(MatrixRole(150, tags: onlyHelper).name, "Owner");
    expect(MatrixRole(20, tags: onlyHelper).name, "Helper");

    final muted = MatrixRole(-1, tags: onlyHelper);
    expect(muted.rank, 0);
    expect(muted.name, "Member");
  });
}
