import 'package:commet/client/client.dart';
import 'package:commet/client/components/component.dart';

abstract class AccountSwitchPrefix<T extends Client> implements Component<T> {
  /// The account [string] should be sent from, and the pattern it used.
  (Client, SendAsPattern)? getPrefixedAccount(String string, Room currentRoom);

  /// Vommet issue 597: the send-as patterns of this account. A plain prefix is
  /// a pattern with only [SendAsPattern.before].
  List<SendAsPattern> get patterns;

  String removePrefix(String string, Room currentRoom);

  Future<void> setPatterns(List<SendAsPattern> patterns);

  bool isPossiblyUsingPrefix(String currentText);
}

/// Text typed [before] and/or [after] a message to send it from another
/// account: a prefix (`p:`), a suffix (`-p`) or a wrapper (`(` and `)`).
class SendAsPattern {
  final String before;
  final String after;

  const SendAsPattern({this.before = "", this.after = ""});

  /// The pattern to store for these fields, or null when both are empty.
  /// Only whitespace on the far side from the message is dropped: "e " keeps
  /// its space, so it does not match "elderberries" (Vommet issue 335).
  static SendAsPattern? normalize(String before, String after) {
    final pattern =
        SendAsPattern(before: before.trimLeft(), after: after.trimRight());
    return pattern.isEmpty ? null : pattern;
  }

  bool get isEmpty => before.isEmpty && after.isEmpty;

  bool get isPrefix => before.isNotEmpty && after.isEmpty;

  /// How much of a message this pattern covers; the longest match wins.
  int get length => before.length + after.length;

  /// The message inside [text], with the spaces next to the pattern removed,
  /// or null when [text] doesn't use this pattern or has nothing inside it.
  String? messageIn(String text) {
    if (isEmpty || text.length < length) return null;
    if (!text.startsWith(before) || !text.endsWith(after)) return null;

    var message = text.substring(before.length, text.length - after.length);
    if (before.isNotEmpty) message = message.trimLeft();
    if (after.isNotEmpty) message = message.trimRight();
    return message.trim().isEmpty ? null : message;
  }

  bool matches(String text) => messageIn(text) != null;

  /// Whether [text] could still turn into a message using this pattern: it
  /// starts with [before], or is the start of it. A suffix can't be told
  /// apart from the message until it is sent.
  bool possiblyMatches(String text) {
    if (before.isEmpty) return false;
    if (text.length >= before.length) return text.startsWith(before);
    return before.startsWith(text);
  }

  /// Whether this pattern wins over [other] when both match: the longer one,
  /// then the one with a [before] part.
  bool beats(SendAsPattern other) {
    if (length != other.length) return length > other.length;
    return before.isNotEmpty && other.before.isEmpty;
  }

  Map<String, String> toJson() => {"before": before, "after": after};

  static SendAsPattern? fromJson(Object? json) {
    if (json is! Map) return null;
    final before = json["before"];
    final after = json["after"];
    return SendAsPattern.normalize(
        before is String ? before : "", after is String ? after : "");
  }

  /// [patterns] without empty and repeated ones, in order.
  static List<SendAsPattern> distinct(Iterable<SendAsPattern> patterns) {
    final result = <SendAsPattern>[];
    for (final pattern in patterns) {
      if (pattern.isEmpty || result.contains(pattern)) continue;
      result.add(pattern);
    }
    return result;
  }

  @override
  bool operator ==(Object other) =>
      other is SendAsPattern && other.before == before && other.after == after;

  @override
  int get hashCode => Object.hash(before, after);

  @override
  String toString() => "$before…$after";
}

/// Vommet issue 597: where the patterns live in the shared
/// `im.fluffychat.account_bundles` account data. FluffyChat only knows the
/// plain `prefix`, so it stays set to the first prefix-only pattern.
class SendAsPatternStorage {
  static const patternsKey = "im.vommet.send_as_patterns";
  static const prefixKey = "prefix";

  static List<SendAsPattern> read(Map<String, Object?>? content) {
    final result = <SendAsPattern>[];
    final stored = content?[patternsKey];
    if (stored is List) {
      result.addAll(stored.map(SendAsPattern.fromJson).nonNulls);
    }

    // A prefix set by FluffyChat or an older Vommet still counts.
    final prefix = content?[prefixKey];
    if (prefix is String) {
      final legacy = SendAsPattern.normalize(prefix, "");
      if (legacy != null && !result.contains(legacy)) result.insert(0, legacy);
    }

    return SendAsPattern.distinct(result);
  }

  /// [content] with [patterns] stored in it.
  static Map<String, Object?> write(
      Map<String, Object?>? content, List<SendAsPattern> patterns) {
    final result = Map<String, Object?>.of(content ?? {});
    patterns = SendAsPattern.distinct(patterns);

    final prefix = patterns.where((p) => p.isPrefix).firstOrNull;
    if (prefix == null) {
      result.remove(prefixKey);
    } else {
      result[prefixKey] = prefix.before;
    }

    if (patterns.isEmpty) {
      result.remove(patternsKey);
    } else {
      result[patternsKey] = patterns.map((p) => p.toJson()).toList();
    }

    return result;
  }
}
