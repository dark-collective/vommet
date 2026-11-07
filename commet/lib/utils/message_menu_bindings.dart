// Vommet issue 1213: device-local bindings, separate from system-wide hotkeys.
import 'dart:convert';

import 'package:commet/utils/common_strings.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum MessageMenuAction {
  reply('R'),
  edit('E'),
  copy('C'),
  delete('D'),
  forward('F'),
  thread('T');

  const MessageMenuAction(this.defaultKey);
  final String defaultKey;

  String get label => switch (this) {
        reply => CommonStrings.promptReply,
        edit => CommonStrings.promptEdit,
        copy => CommonStrings.promptCopy,
        delete => CommonStrings.promptDelete,
        forward => Intl.message(
            'Forward',
            name: 'menuKeyForward',
            desc: 'Message menu shortcut action that forwards a message',
          ),
        thread => Intl.message(
            'Reply in thread',
            name: 'menuKeyReplyInThread',
            desc: 'Message menu shortcut action that replies in a thread',
          ),
      };
}

class MessageMenuBindings {
  MessageMenuBindings(this.preferences);
  final SharedPreferences? preferences;
  static const storageKey = 'vommet_message_menu_keys';

  Map<MessageMenuAction, String?> get keys {
    Map<String, dynamic> saved = {};
    try {
      saved = jsonDecode(preferences?.getString(storageKey) ?? '{}')
          as Map<String, dynamic>;
    } on FormatException {
      // Invalid persisted data uses the defaults.
    } on TypeError {
      // Invalid persisted data uses the defaults.
    }
    final result = {
      for (final action in MessageMenuAction.values)
        action: saved.containsKey(action.name)
            ? normalize(
                saved[action.name] is String
                    ? saved[action.name] as String
                    : '',
              )
            : action.defaultKey,
    };
    // Corrupt/stale duplicates must never dispatch an unexpected action.
    final values = result.values.toList();
    for (final action in result.keys) {
      final key = result[action];
      if (key != null && values.where((v) => v == key).length > 1)
        result[action] = null;
    }
    return result;
  }

  static String? normalize(String value) {
    final key = value.toUpperCase();
    return RegExp(r'^[A-Z]$').hasMatch(key) ? key : null;
  }

  MessageMenuAction? conflict(MessageMenuAction action, String key) {
    for (final entry in keys.entries) {
      if (entry.key != action && entry.value == normalize(key))
        return entry.key;
    }
    return null;
  }

  Future<bool> set(MessageMenuAction action, String? key) async {
    final normalized = key == null ? null : normalize(key);
    if (key != null && (normalized == null || conflict(action, key) != null))
      return false;
    final updated = keys..[action] = normalized;
    final overrides = {
      for (final entry in updated.entries)
        if (entry.value != entry.key.defaultKey)
          entry.key.name: entry.value ?? '',
    };
    if (overrides.isEmpty) {
      await reset();
    } else {
      await preferences?.setString(storageKey, jsonEncode(overrides));
    }
    return true;
  }

  Future<void> reset() async => preferences?.remove(storageKey);
}
