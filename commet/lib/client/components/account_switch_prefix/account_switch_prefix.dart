import 'package:commet/client/client.dart';
import 'package:commet/client/components/component.dart';

abstract class AccountSwitchPrefix<T extends Client> implements Component<T> {
  (Client, String)? getPrefixedAccount(String string, Room currentRoom);

  String? get clientPrefix;

  String removePrefix(String string, Room currentRoom);

  Future<void> setClientPrefix(String? prefix);

  bool isPossiblyUsingPrefix(String currentText);
}

class AccountPrefixText {
  /// The prefix to store for [input], or null to clear it. Only leading
  /// whitespace is dropped: a trailing space is part of the prefix, so "e "
  /// does not match "elderberries".
  static String? normalize(String? input) {
    if (input == null) return null;
    final prefix = input.trimLeft();
    return prefix.isEmpty ? null : prefix;
  }

  static bool matches(String text, String prefix) =>
      prefix.isNotEmpty && text.startsWith(prefix);

  /// Whether [text] could still turn into a message using [prefix]: either it
  /// already starts with the prefix, or it is the start of the prefix.
  static bool possiblyMatches(String text, String prefix) {
    if (prefix.isEmpty) return false;
    if (text.length >= prefix.length) return text.startsWith(prefix);
    return prefix.startsWith(text);
  }

  /// [text] without [prefix] and the whitespace after it.
  static String remove(String text, String prefix) {
    if (!matches(text, prefix)) return text;
    return text.substring(prefix.length).trimLeft();
  }
}
