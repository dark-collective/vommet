// Vommet: identity per place, name safety (rules R1, R2 and R5). Anyone can set
// any name and picture in a room from any Matrix app, so this protects the
// viewer: when someone shows a name that looks like another member's, or one
// of your contacts', or the same picture file, their Matrix ID is shown next
// to the name. It never blocks or changes anyone's name.
import 'dart:async';

import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/matrix_member.dart';
import 'package:commet/client/matrix/components/petname/matrix_petname_component.dart';
import 'package:commet/client/matrix/nicknames/nickname_experiment.dart';
import 'package:commet/client/member.dart';
import 'package:commet/utils/bridged_users.dart';
import 'package:matrix/matrix.dart' as matrix;

/// One person as name safety sees them: the name and picture they show.
class NameSafetyEntry {
  final String id;
  final String? name;
  final String? avatar;

  const NameSafetyEntry(this.id, this.name, [this.avatar]);
}

class NameSafety {
  /// Letters that look alike, after lowercasing, mapped to one of them
  /// (a short form of the Unicode confusables list: Cyrillic, Greek,
  /// accented Latin, digits).
  static const Map<String, String> _lookalikes = {
    // Cyrillic
    "а": "a", "в": "b", "г": "r", "е": "e", "ё": "e", "з": "3", "і": "l",
    "ї": "l", "ј": "j", "к": "k", "м": "m", "н": "h", "о": "o", "п": "n",
    "р": "p", "с": "c", "т": "t", "у": "y", "х": "x", "ѕ": "s", "ԁ": "d",
    "һ": "h", "ӏ": "l", "ԛ": "q", "ԝ": "w", "ь": "b",
    // Greek
    "α": "a", "β": "b", "ε": "e", "η": "n", "ι": "l", "κ": "k", "ν": "v",
    "ο": "o", "ρ": "p", "τ": "t", "υ": "u", "χ": "x", "ζ": "z", "γ": "y",
    // Accented Latin
    "à": "a", "á": "a", "â": "a", "ã": "a", "ä": "a", "å": "a", "ā": "a",
    "ç": "c", "è": "e", "é": "e", "ê": "e", "ë": "e", "ē": "e", "ì": "l",
    "í": "l", "î": "l", "ï": "l", "ñ": "n", "ò": "o", "ó": "o", "ô": "o",
    "õ": "o", "ö": "o", "ø": "o", "ù": "u", "ú": "u", "û": "u", "ü": "u",
    "ý": "y", "ÿ": "y", "ı": "l", "ł": "l",
    // Digits and marks that pass for letters
    "0": "o", "1": "l", "i": "l", "|": "l",
  };

  /// Characters left out when comparing: spaces, separators, zero-width
  /// and direction controls, combining marks, variation selectors.
  static bool _ignored(int c) =>
      c <= 0x20 ||
      c == 0x2E || // .
      c == 0x5F || // _
      c == 0x2D || // -
      c == 0x27 || // '
      c == 0xA0 ||
      (c >= 0x0300 && c <= 0x036F) ||
      (c >= 0x2000 && c <= 0x200F) ||
      (c >= 0x2028 && c <= 0x202F) ||
      (c >= 0x2060 && c <= 0x206F) ||
      (c >= 0xFE00 && c <= 0xFE0F) ||
      c == 0x3000 ||
      c == 0xFEFF;

  /// The form two names are compared in: names with the same key look
  /// alike. Ignores case, spaces and separators, and lookalike letters
  /// (Cyrillic "А" is Latin "A", "rn" is "m", "1" is "l").
  static String key(String name) {
    final out = StringBuffer();
    for (final rune in name.toLowerCase().runes) {
      if (_ignored(rune)) continue;
      var c = rune;
      // Fullwidth forms to ASCII.
      if (c >= 0xFF01 && c <= 0xFF5E) c -= 0xFEE0;
      final s = String.fromCharCode(c).toLowerCase();
      out.write(_lookalikes[s] ?? s);
    }
    return out.toString().replaceAll("rn", "m").replaceAll("vv", "w");
  }

  /// Words that claim a role in a room, compared as [key]s (so "Аdmin" with
  /// a Cyrillic "А" or "M0D" count too). A trailing "s" is dropped.
  static final Set<String> _roleWords = {
    for (final w in [
      "admin",
      "administrator",
      "mod",
      "moderator",
      "staff",
      "official",
      "support",
    ])
      key(w),
  };

  /// Check marks and shields that pass for a verified badge.
  static const Set<int> _badges = {
    0x2611, // ☑
    0x2705, // ✅
    0x2713, // ✓
    0x2714, // ✔
    0x1F6E1, // 🛡
  };

  /// Whether [name] claims a role or a badge: a role word such as admin,
  /// mod, staff, official or support on its own (not inside another word),
  /// or a check mark or shield.
  static bool claimsRole(String name) {
    if (name.runes.any(_badges.contains)) return true;
    bool isRole(String word) {
      final k = key(word);
      if (k.isEmpty) return false;
      return _roleWords.contains(k) ||
          (k.length > 1 &&
              k.endsWith("s") &&
              _roleWords.contains(k.substring(0, k.length - 1)));
    }

    if (isRole(name)) return true;
    // Split on spaces and punctuation, keeping zero-width and combining
    // characters inside words (key leaves those out).
    return name
        .split(RegExp(r"[^\p{L}\p{N}\p{M}\p{Cf}]+", unicode: true))
        .any(isRole);
  }

  /// The [members] of one room whose name looks like another member's or
  /// one of [contacts]', or whose picture is the same file as someone
  /// else's. People in [trusted] (you, and people you named yourself) are
  /// never flagged, but others are still checked against them.
  /// Network marks: with [groups] (id → mark group, see `markGroup`), only
  /// people in the same group clash; anyone missing is "plain".
  static Set<String> flag(
      Iterable<NameSafetyEntry> members, Iterable<NameSafetyEntry> contacts,
      {Set<String> trusted = const {}, Map<String, String>? groups}) {
    final byName = <String, Set<String>>{};
    final byAvatar = <String, Set<String>>{};
    final all = [...members, ...contacts];
    String group(String id) => groups == null ? "" : groups[id] ?? "plain";
    for (final e in all) {
      final name = e.name;
      if (name != null && name.trim().isNotEmpty) {
        final k = key(name);
        if (k.isNotEmpty) (byName["${group(e.id)}\u0000$k"] ??= {}).add(e.id);
      }
      final avatar = e.avatar;
      if (avatar != null && avatar.isNotEmpty) {
        (byAvatar["${group(e.id)}\u0000$avatar"] ??= {}).add(e.id);
      }
    }

    bool shared(Set<String>? ids, String id) =>
        ids != null && ids.any((other) => other != id);

    final result = <String>{};
    for (final e in members) {
      if (trusted.contains(e.id)) continue;
      final name = e.name;
      final nameKey = name == null ? "" : key(name);
      final g = group(e.id);
      if ((nameKey.isNotEmpty && shared(byName["$g\u0000$nameKey"], e.id)) ||
          (e.avatar != null && shared(byAvatar["$g\u0000${e.avatar}"], e.id))) {
        result.add(e.id);
      }
    }
    return result;
  }

  /// The name to show for [member] where a sender is named: with the Matrix
  /// ID after it when the name or picture collides.
  static String label(Member member) {
    if (member is MatrixMember &&
        MatrixNameSafety.of(member.client).collides(member.matrixUser)) {
      return "${member.displayName} (${member.identifier})";
    }
    return member.displayName;
  }
}

/// Name safety for one account: works out, per room, who to flag, and keeps
/// it until the next sync touches that room.
class MatrixNameSafety {
  static final Expando<MatrixNameSafety> _instances = Expando();

  static MatrixNameSafety of(MatrixClient client) =>
      _instances[client] ??= MatrixNameSafety._(client);

  static bool get enabled => experimentNameSafety.value;

  final MatrixClient client;
  matrix.Client get _mx => client.matrixClient;

  final Map<String, Set<String>> _flagged = {};
  List<NameSafetyEntry>? _contacts;
  Set<String>? _trusted;
  StreamSubscription? _sync;
  StreamSubscription? _marks;
  Map<String, String>? _contactGroups;

  MatrixNameSafety._(this.client) {
    _sync = _mx.onSync.stream.listen(_onSync);
    // Network marks: a verified icon or a setting changed who clashes.
    _marks = BridgedUsers.onAnyChange.listen((_) {
      _flagged.clear();
      _contactGroups = null;
    });
  }

  void _onSync(matrix.SyncUpdate update) {
    if (update.accountData?.isNotEmpty == true) {
      _flagged.clear();
      _contacts = null;
      _contactGroups = null;
      _trusted = null;
      return;
    }
    final joined = update.rooms?.join?.keys;
    if (joined == null) return;
    for (final id in joined) {
      _flagged.remove(id);
      if (_contacts != null && _mx.getRoomById(id)?.isDirectChat == true) {
        _contacts = null;
        _contactGroups = null;
        _flagged.clear();
        return;
      }
    }
  }

  /// Whether [user] (a member of [matrix.User.room]) shows a name or
  /// picture someone else there, or one of your contacts, also has, or
  /// claims a role they don't hold there.
  bool collides(matrix.User user) {
    if (!enabled || user.id == _mx.userID) return false;
    final room = user.room;
    final flagged = _flagged[room.id] ??= _compute(room);
    return flagged.contains(user.id);
  }

  /// Power level from which a role word in the name is genuine.
  static const int moderatorLevel = 50;

  Set<String> _compute(matrix.Room room) {
    final trusted = _trustedOnce();
    final participants = room.getParticipants();
    // A direct message has one other person; nobody to mix them up with.
    // A role word there is always marked: nobody moderates a DM, and both
    // people usually hold the top level in it.
    final direct = room.isDirectChat;
    final result = direct
        ? <String>{}
        : NameSafety.flag([
            for (final u in participants)
              NameSafetyEntry(u.id, u.displayName, u.avatarUrl?.toString()),
          ], _contactsOnce(),
            trusted: trusted, groups: _groups(room, participants));
    for (final u in participants) {
      if (trusted.contains(u.id)) continue;
      final name = u.displayName;
      if (name == null || !NameSafety.claimsRole(name)) continue;
      if (direct || room.getPowerLevelByUserId(u.id) < moderatorLevel) {
        result.add(u.id);
      }
    }
    return result;
  }

  /// Network marks: who shows which verified network icon here (contacts
  /// without a room). Null with the marks off: everyone clashes, as before.
  Map<String, String>? _groups(
      matrix.Room room, List<matrix.User> participants) {
    if (!BridgedUsers.mark.value) return null;
    final commetRoom = client.getRoom(room.id);
    final contacts = _contactGroups ??= {
      for (final c in _contactsOnce())
        c.id: BridgedUsers.markGroupOf(client, c.id),
    };
    return {
      ...contacts,
      for (final u in participants)
        u.id: BridgedUsers.markGroupOf(client, u.id, room: commetRoom),
    };
  }

  /// Your DM partners and the people you gave a name: as they show in the
  /// DM, and under your name for them.
  List<NameSafetyEntry> _contactsOnce() => _contacts ??= [
        for (final room in _mx.rooms)
          if (room.isDirectChat && room.directChatMatrixID != null)
            () {
              final id = room.directChatMatrixID!;
              final u = room.unsafeGetUserFromMemoryOrFallback(id);
              return NameSafetyEntry(
                  id, u.displayName, u.avatarUrl?.toString());
            }(),
        for (final e in _petNames().entries)
          if (e.value is String) NameSafetyEntry(e.key, e.value as String),
      ];

  Set<String> _trustedOnce() => _trusted ??= {
        if (_mx.userID != null) _mx.userID!,
        ..._petNames().keys,
      };

  Map<String, Object?> _petNames() =>
      _mx.accountData[MatrixPetNameComponent.key]?.content ?? const {};

  void dispose() {
    _sync?.cancel();
    _marks?.cancel();
  }
}
