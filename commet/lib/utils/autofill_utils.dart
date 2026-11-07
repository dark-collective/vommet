import 'package:commet/client/client.dart';
import 'package:commet/client/components/command/command_component.dart';
import 'package:commet/client/components/quick_replies/quick_replies.dart';
import 'package:commet/client/components/emoticon/emoji_pack.dart';
import 'package:commet/client/components/emoticon/emoticon.dart';
import 'package:commet/client/components/emoticon/emoticon_component.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/client/matrix/matrix_space.dart';
import 'package:commet/client/timeline_events/timeline_event_message.dart';
import 'package:commet/utils/emoji/unicode_emoji.dart';
import 'package:flutter/material.dart';
import 'package:fuzzy/fuzzy.dart';
import 'package:matrix/matrix.dart' as matrix;

class AutofillUtils {
  static List<AutofillSearchResult> search(String string, Client client,
      {Room? room}) {
    List<AutofillSearchResult>? results;

    var firstChar = string.characters.first;

    string = string.substring(1);
    switch (firstChar) {
      case "/":
        results = room != null ? searchCommands(string, room) : null;
        string = string.replaceAll("/", "");
        break;
      case "#":
        // Vommet issue 1223: room search owns both filtering and final ranking.
        return room != null && identical(room.client, client)
            ? searchRooms(string, room)
            : [];
      case "@":
        results = room != null ? searchUsers(string, room) : null;
        break;
      case ":":
        // Vommet issue 1137: this search already ranks and bounds matches.
        // Filtering again by the display name would discard alias matches
        // and undo custom-first ordering for exact shortcode collisions.
        return searchEmoticon(string, client: client, room: room);

      default:
        break;
    }

    if (results == null) {
      return [];
    }

    var fuzzy = Fuzzy<AutofillSearchResult>(results,
        options: FuzzyOptions(keys: [
          WeightedKey(
              name: "alternate",
              getter: (obj) {
                return obj.alternateSearchTerm ?? "";
              },
              weight: 1),
          WeightedKey(
              name: "result",
              getter: (result) {
                return result.result;
              },
              weight: 1)
        ]));

    return fuzzy.search(string, 20).map((e) {
      return e.item;
    }).toList();
  }

  static List<AutofillSearchResult> searchCommands(String string, Room room) {
    // Vommet: your quick replies first, then the commands.
    final quickReplies = QuickReplies.autofill(room.client);
    var component = room.client.getComponent<CommandComponent>();
    if (component != null) {
      var result = component.getCommands();
      return [
        ...quickReplies,
        ...result.map((e) => AutofillSearchResult(e, "/$e")),
      ];
    } else {
      return quickReplies;
    }
  }

  static List<AutofillSearchResult> searchUsers(String string, Room room) {
    List<AutofillSearchResult> results = List.empty(growable: true);

    Set<String> recentUsers = {};
    if (string.isEmpty) {
      var tl = room.timeline;
      if (tl != null) {
        recentUsers = tl.events
            .where((i) => i is TimelineEventMessage)
            .map((i) => i.senderId)
            .toSet();

        results = recentUsers.map((i) {
          var member = room.getMemberOrFallback(i);
          return AutofillSearchResultAvatar(
              member.displayName,
              member.identifier,
              member.avatar,
              member.defaultColor) as AutofillSearchResult;
        }).toList(growable: true);
      }
    }

    var result = room.memberIds
        .where((i) => !recentUsers.contains(i))
        .map((e) => room.getMemberOrFallback(e))
        .toList();

    results.addAll(result
        .map((e) => AutofillSearchResultAvatar(
                e.displayName, e.identifier, e.avatar, e.defaultColor)
            as AutofillSearchResult)
        .toList(growable: true));

    if (room.permissions.canMentionRoom) {
      results.add(AutofillSearchResult("@room", "@room",
          alternateSearchTerm: "@everyone"));
    }

    return results;
  }

  // Vommet issue 1223: search only this account's loaded, joined metadata.
  // Keep room ranking here: the generic second fuzzy pass loses related priority.
  static List<AutofillSearchResult> searchRooms(String string, Room room) {
    final client = room.client;
    final spaces = client.spaces
        .whereType<MatrixSpace>()
        .where((space) =>
            identical(space.client, client) &&
            space.matrixRoom.membership == matrix.Membership.join)
        .toList();
    final parents = <String, Set<String>>{};
    final byId = {for (final space in spaces) space.identifier: space};
    for (final space in spaces) {
      for (final child in space.rooms) {
        if (identical(child.client, client)) {
          (parents[child.identifier] ??= {}).add(space.identifier);
        }
      }
      for (final child in space.subspaces) {
        if (identical(child.client, client)) {
          (parents[child.identifier] ??= {}).add(space.identifier);
        }
      }
    }
    final related = <String>{};
    final visited = <String>{room.identifier};
    final pending = [room.identifier];
    while (pending.isNotEmpty) {
      for (final id in parents[pending.removeLast()] ?? <String>{}) {
        if (!visited.add(id)) continue;
        pending.add(id);
        related.add(id);
        related.addAll(byId[id]!
            .rooms
            .where((r) => identical(r.client, client))
            .map((r) => r.identifier));
      }
    }

    final candidates = <_RoomAutofillResult>[];
    final seen = <String>{};
    void add(String id, String name, Client owner, matrix.Room sdkRoom) {
      if (!identical(owner, client) ||
          sdkRoom.membership != matrix.Membership.join ||
          seen.contains(id)) return;
      final content = sdkRoom.getState('m.room.canonical_alias')?.content;
      final alternatives = content?['alt_aliases'];
      final addresses = <String>{
        for (final value in [
          content?['alias'],
          if (alternatives is List) ...alternatives
        ])
          if (value is String &&
              value.startsWith('#') &&
              matrix.MatrixIdExtension(value).isValidMatrixId &&
              !RegExp(r'\s').hasMatch(value))
            value,
      };
      if (addresses.isEmpty) return;
      seen.add(id);
      for (final address in addresses) {
        candidates.add(_RoomAutofillResult(name, addresses.first,
            identifier: id,
            related: related.contains(id),
            order: candidates.length,
            alias: address.substring(1)));
      }
    }

    for (final candidate in client.rooms.whereType<MatrixRoom>()) {
      add(candidate.identifier, candidate.displayName, candidate.client,
          candidate.matrixRoom);
    }
    for (final space in spaces) {
      add(space.identifier, space.displayName, space.client, space.matrixRoom);
    }
    final matches = Fuzzy<_RoomAutofillResult>(candidates,
        options: FuzzyOptions(keys: [
          WeightedKey(name: 'name', getter: (r) => r.result, weight: 1),
          WeightedKey(
              name: 'alias', getter: (r) => r.alternateSearchTerm!, weight: 1),
        ])).search(string);
    matches.sort((a, b) {
      if (a.item.related != b.item.related) return a.item.related ? -1 : 1;
      final score = a.score.compareTo(b.score);
      return score != 0 ? score : a.item.order.compareTo(b.item.order);
    });
    final emitted = <String>{};
    return matches
        .where((m) => emitted.add(m.item.identifier))
        .take(20)
        .map((m) => m.item)
        .toList();
  }

  static List<AutofillSearchResult> searchEmoticon(String string,
      {int limit = 20,
      required Client client,
      Room? room,
      double threshold = 0.2}) {
    List<EmoticonPack>? packs;
    if (room != null) {
      var emoticons = room.getComponent<RoomEmoticonComponent>();
      packs = emoticons?.availableEmoji;
    } else {
      var emoticons = client.getComponent<EmoticonComponent>();
      packs = emoticons?.availablePacks;
    }

    if (packs == null || limit <= 0) return [];

    // Vommet issue 1137: aliases are search keys, not additional emoji rows.
    // Keep the best match per stock slug across packs, before applying limits.
    final matches = <Object, AutofillSearchResultEmoticon>{};
    for (final pack in packs) {
      final entries = pack is UnicodeEmoticonPack
          ? pack.shortcodeEntries
          : [
              for (final emoji in pack.emoji)
                if (emoji.shortcode != null) MapEntry(emoji.shortcode!, emoji),
            ];
      final fuzzy = Fuzzy<MapEntry<String, Emoticon>>(
        entries,
        options: FuzzyOptions(
          threshold: threshold,
          keys: [
            WeightedKey(
              name: 'shortcode',
              getter: (entry) => entry.key,
              weight: 1,
            ),
          ],
        ),
      );
      for (final match in fuzzy.search(string)) {
        final emoji = match.item.value;
        final key = emoji is UnicodeEmoticon ? emoji.slug : Object();
        final previous = matches[key];
        if (previous == null || match.score < previous.score) {
          matches[key] = AutofillSearchResultEmoticon(
            emoji.shortcode!,
            emoji.slug,
            emoji,
            score: match.score,
            alternateSearchTerm: match.item.key,
          );
        }
      }
    }

    final result = matches.values.toList();
    final order = {for (var i = 0; i < result.length; i++) result[i]: i};
    result.sort((a, b) {
      final score = a.score.compareTo(b.score);
      if (score != 0) return score;
      // Typed exact custom names keep their priority over stock aliases.
      if (a.alternateSearchTerm == string && b.alternateSearchTerm == string) {
        final aStock = a.emoticon is UnicodeEmoticon;
        final bStock = b.emoticon is UnicodeEmoticon;
        if (aStock != bStock) return aStock ? 1 : -1;
      }
      return order[a]!.compareTo(order[b]!);
    });
    return result.take(limit).toList();
  }
}

class AutofillSearchResult {
  String result;
  String slug;
  String? alternateSearchTerm;
  AutofillSearchResult(this.result, this.slug, {this.alternateSearchTerm});
}

class AutofillSearchResultAvatar extends AutofillSearchResult {
  ImageProvider? image;
  Color fallbackColor;

  AutofillSearchResultAvatar(
      super.result, super.slug, this.image, this.fallbackColor);
}

class AutofillSearchResultEmoticon extends AutofillSearchResult {
  Emoticon emoticon;
  double score;
  // Vommet issue 1137: keep the matched alias without changing its label.
  AutofillSearchResultEmoticon(super.result, super.slug, this.emoticon,
      {this.score = 0, super.alternateSearchTerm});
}

// Vommet issue 1223: each alias can match, but a room is emitted only once.
class _RoomAutofillResult extends AutofillSearchResult {
  final String identifier;
  final bool related;
  final int order;
  _RoomAutofillResult(super.result, super.slug,
      {required this.identifier,
      required this.related,
      required this.order,
      required String alias})
      : super(alternateSearchTerm: alias);
}
