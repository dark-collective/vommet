import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/client/components/command/command_component.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/utils/autofill_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart' as matrix;

/// Vommet: a saved text you insert by typing `/name` in the message box.
class QuickReply {
  final String name;
  final String body;
  const QuickReply({required this.name, required this.body});

  static QuickReply? fromJson(Object? json) {
    if (json is! Map) return null;
    final name = json["name"];
    final body = json["body"];
    if (name is! String || body is! String) return null;
    if (!QuickReplies.validName(name) || body.trim().isEmpty) return null;
    return QuickReply(name: name, body: body);
  }

  Map<String, Object?> toJson() => {"name": name, "body": body};
}

/// Why a quick reply's name can't be used.
enum QuickReplyNameProblem { empty, invalid, command, taken }

/// Vommet: your quick replies, in your private account data
/// (`im.nether.vommet.quick_replies`), so they follow you to your other
/// devices. The homeserver can read them. Other apps don't show them.
class QuickReplies {
  static const String type = "im.nether.vommet.quick_replies";
  static const int version = 1;
  static const int maxItems = 100;
  static const int maxNameLength = 32;

  /// Bumps whenever your quick replies change, here or on another device.
  static final ValueNotifier<int> changed = ValueNotifier(0);

  static final Map<matrix.Client, StreamSubscription> _watching = {};
  static final RegExp _name = RegExp(r"^[A-Za-z0-9-]+$");

  static matrix.Client? _matrixClient(Client client) =>
      client is MatrixClient ? client.matrixClient : null;

  static bool supported(Client client) => _matrixClient(client) != null;

  /// In your order.
  static List<QuickReply> of(Client client) {
    final mx = _matrixClient(client);
    if (mx == null) return const [];
    _watch(mx);
    return parse(mx.accountData[type]?.content);
  }

  /// In order, first of each name (case-insensitive) kept, bad ones skipped.
  static List<QuickReply> parse(Map<String, Object?>? content) {
    final items = content?["items"];
    if (items is! List) return const [];
    final seen = <String>{};
    final result = <QuickReply>[];
    for (final item in items) {
      final q = QuickReply.fromJson(item);
      if (q == null || !seen.add(q.name.toLowerCase())) continue;
      result.add(q);
      if (result.length >= maxItems) break;
    }
    return result;
  }

  /// For the `/` suggestions: "name · start of the text"; picking one puts
  /// the whole text in the message box, to edit before sending.
  static List<AutofillSearchResult> autofill(Client client) => [
        for (final q in of(client))
          AutofillSearchResult("${q.name} · ${preview(q.body)}", q.body,
              alternateSearchTerm: q.name),
      ];

  static String preview(String body, {int length = 40}) {
    final line = body.trim().replaceAll(RegExp(r"\s+"), " ");
    return line.length <= length ? line : "${line.substring(0, length)}…";
  }

  static Map<String, Object?> serialize(List<QuickReply> items) => {
        "version": version,
        "items": items.take(maxItems).map((q) => q.toJson()).toList(),
      };

  static bool validName(String name) =>
      name.length <= maxNameLength && _name.hasMatch(name);

  /// Built-in commands of this account (`/status`, `/me`, ...), lower-cased.
  static Set<String> commandNames(Client client) =>
      (client.getComponent<CommandComponent>()?.getCommands() ?? const [])
          .map((c) => c.toLowerCase())
          .toSet();

  /// Null when [name] can be used. [editing] is the name being renamed.
  static QuickReplyNameProblem? checkName(String name,
      {required Set<String> commands,
      required List<QuickReply> existing,
      String? editing}) {
    if (name.isEmpty) return QuickReplyNameProblem.empty;
    if (!validName(name)) return QuickReplyNameProblem.invalid;
    final lower = name.toLowerCase();
    if (commands.contains(lower)) return QuickReplyNameProblem.command;
    if (existing.any((q) =>
        q.name.toLowerCase() == lower &&
        q.name.toLowerCase() != editing?.toLowerCase())) {
      return QuickReplyNameProblem.taken;
    }
    return null;
  }

  /// Adds or replaces the quick reply called [previousName] (or [reply]'s).
  static Future<void> put(Client client, QuickReply reply,
      {String? previousName}) {
    final key = (previousName ?? reply.name).toLowerCase();
    final items = [...of(client)];
    final i = items.indexWhere((q) => q.name.toLowerCase() == key);
    if (i >= 0) {
      items[i] = reply;
    } else {
      items.add(reply);
    }
    return set(client, items);
  }

  static Future<void> remove(Client client, String name) => set(
      client,
      of(client)
          .where((q) => q.name.toLowerCase() != name.toLowerCase())
          .toList());

  static Future<void> set(Client client, List<QuickReply> items) async {
    final mx = _matrixClient(client);
    if (mx == null) return;
    final content = serialize(items);
    await mx.setAccountData(mx.userID!, type, content);
    // Show it now rather than when the sync echoes it back.
    mx.accountData[type] = matrix.BasicEvent(type: type, content: content);
    changed.value++;
  }

  static void _watch(matrix.Client client) {
    if (_watching.containsKey(client)) return;
    _watching[client] = client.onSync.stream.listen((sync) {
      if (sync.accountData?.any((e) => e.type == type) == true) {
        changed.value++;
      }
    });
  }
}
