// Vommet (New Home): the Rooms page's logic, kept free of the SDK and of
// widgets so it can be unit tested: the chips, the tree of standalone rooms
// and spaces (with nested subspaces), and the live search over all of it.

/// The Rooms page's filter chips.
enum RoomsChip {
  all("All rooms & spaces", "All"),
  standalone("Standalone", "Standalone"),
  voice("Voice", "Voice"),
  photos("Photos", "Photos"),
  calendars("Calendars", "Calendars"),
  unread("Unread", "Unread");

  const RoomsChip(this.label, this.shortLabel);
  final String label;

  /// The label on phones, where the chips scroll sideways.
  final String shortLabel;
}

/// A room's kind, from Vommet's room types (chat, Voice Chat, Photo Album,
/// Calendar).
enum RoomKind { chat, voice, photos, calendar }

/// The name of rooms that aren't in any space.
const String standaloneRoomsTitle = "Standalone rooms";

/// A space (or subspace) and what's in it, as the page needs it.
class SpaceNode<S, R> {
  SpaceNode(this.space, this.name, this.key,
      {this.rooms = const [], this.subspaces = const []});
  final S space;
  final String name;

  /// Unique and stable per space, for collapse state and widget keys.
  final String key;
  final List<R> rooms;
  final List<SpaceNode<S, R>> subspaces;
}

/// How the page reads a room. Lets tests use plain objects.
class RoomFacts<R> {
  const RoomFacts(
      {required this.name,
      required this.kind,
      required this.unread,
      required this.lastActivity});
  final String Function(R room) name;
  final RoomKind Function(R room) kind;
  final bool Function(R room) unread;
  final DateTime Function(R room) lastActivity;
}

/// A filtered section of the tree: the standalone rooms, or one space with
/// its matching rooms and subspaces.
class RoomsSection<S, R> {
  RoomsSection(this.node, this.rooms, this.subsections, {required this.depth});

  /// Null for the standalone rooms.
  final SpaceNode<S, R>? node;
  final List<R> rooms;
  final List<RoomsSection<S, R>> subsections;
  final int depth;

  String get key => node?.key ?? "standalone";
  String get name => node?.name ?? standaloneRoomsTitle;

  /// Rooms here and in every subsection.
  int get count =>
      rooms.length + subsections.fold(0, (sum, s) => sum + s.count);

  /// Subspaces at any depth, for a collapsed space's summary.
  int get subspaceCount =>
      subsections.fold(0, (sum, s) => sum + 1 + s.subspaceCount);
}

/// One search hit: a room, or a space or subspace whose name matches.
class RoomsHit<S, R> {
  RoomsHit.room(R this.room, this.path, this.name, this.match)
      : space = null,
        node = null;
  RoomsHit.space(SpaceNode<S, R> this.node, this.path, this.match)
      : space = node.space,
        room = null,
        name = node.name;

  final R? room;
  final S? space;
  final SpaceNode<S, R>? node;
  final String name;

  /// The spaces it sits in, outermost first; empty for a standalone room
  /// or a top-level space.
  final List<String> path;

  /// Where the query matched in [name].
  final TextMatch match;

  bool get isSpace => node != null;

  /// The muted breadcrumb: "Gaming Guild › Retro", "Standalone" for a room
  /// outside any space, "Space" for a top-level space.
  String get breadcrumb {
    if (path.isNotEmpty) return path.join(" › ");
    return isSpace ? "Space" : "Standalone";
  }
}

/// A match of the query in a name: [start] and [end] in its characters.
class TextMatch {
  const TextMatch(this.start, this.end, this.score);
  final int start;
  final int end;

  /// 0: the name starts with the query, 1: a word does, 2: anywhere.
  final int score;
}

class RoomsModel {
  /// Where [query] (trimmed, any case) matches [name], or null.
  static TextMatch? match(String name, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return null;
    final n = name.toLowerCase();
    final at = n.indexOf(q);
    if (at < 0) return null;
    if (at == 0) return TextMatch(0, q.length, 0);
    // Prefer a match at the start of a word.
    final word = RegExp(r"[\s\-_#.]" + RegExp.escape(q)).firstMatch(n);
    if (word != null) {
      return TextMatch(word.start + 1, word.start + 1 + q.length, 1);
    }
    return TextMatch(at, at + q.length, 2);
  }

  /// Whether [room] belongs under [chip] (the room filters; All and
  /// Standalone keep every room, Standalone drops the spaces instead).
  static bool roomPasses<R>(R room, RoomsChip chip, RoomFacts<R> facts) =>
      switch (chip) {
        RoomsChip.all || RoomsChip.standalone => true,
        RoomsChip.voice => facts.kind(room) == RoomKind.voice,
        RoomsChip.photos => facts.kind(room) == RoomKind.photos,
        RoomsChip.calendars => facts.kind(room) == RoomKind.calendar,
        RoomsChip.unread => facts.unread(room),
      };

  static List<R> _newestFirst<R>(Iterable<R> rooms, RoomFacts<R> facts) => rooms
      .toList()
    ..sort((a, b) => facts.lastActivity(b).compareTo(facts.lastActivity(a)));

  /// The tree for [chip] without a search: Standalone rooms first (when
  /// any pass), then each space with its passing rooms and subspaces.
  /// Spaces and subspaces with nothing passing are left out; their names
  /// come back in [RoomsTree.without] so the page can say so.
  static RoomsTree<S, R> tree<S, R>(
      {required List<R> standalone,
      required List<SpaceNode<S, R>> spaces,
      required RoomsChip chip,
      required RoomFacts<R> facts}) {
    final sections = <RoomsSection<S, R>>[];
    final rooms = _newestFirst(
        standalone.where((r) => roomPasses(r, chip, facts)), facts);
    if (rooms.isNotEmpty) sections.add(RoomsSection(null, rooms, [], depth: 0));
    final without = <String>[];
    if (chip != RoomsChip.standalone) {
      for (final space in spaces) {
        final section = _section(space, chip, facts, 0, {});
        if (section == null) {
          without.add(space.name);
        } else {
          sections.add(section);
        }
      }
    }
    return RoomsTree(sections, without);
  }

  static RoomsSection<S, R>? _section<S, R>(SpaceNode<S, R> node,
      RoomsChip chip, RoomFacts<R> facts, int depth, Set<String> seen) {
    // A space that (wrongly) contains itself further down stops here.
    if (!seen.add(node.key)) return null;
    final rooms = _newestFirst(
        node.rooms.where((r) => roomPasses(r, chip, facts)), facts);
    final subsections = <RoomsSection<S, R>>[
      for (final sub in node.subspaces)
        if (_section(sub, chip, facts, depth + 1, {...seen}) case final s?) s
    ];
    if (rooms.isEmpty && subsections.isEmpty) return null;
    return RoomsSection(node, rooms, subsections, depth: depth);
  }

  /// Search results for [query] over every standalone room, space, subspace
  /// and room in them, for [chip]. Each room shows once (where it was first
  /// found). Best match first (name starts with the query, then a word
  /// does, then anywhere), rooms before spaces, newest activity first.
  /// Spaces only show under All.
  static List<RoomsHit<S, R>> search<S, R>(
      {required String query,
      required List<R> standalone,
      required List<SpaceNode<S, R>> spaces,
      required RoomsChip chip,
      required RoomFacts<R> facts,
      required Object Function(R room) identity}) {
    final hits = <RoomsHit<S, R>>[];
    final seenRooms = <Object>{};
    final seenSpaces = <String>{};

    void addRoom(R room, List<String> path) {
      if (!seenRooms.add(identity(room))) return;
      if (!roomPasses(room, chip, facts)) return;
      final name = facts.name(room);
      final m = match(name, query);
      if (m != null) hits.add(RoomsHit.room(room, path, name, m));
    }

    void walk(SpaceNode<S, R> node, List<String> path) {
      if (!seenSpaces.add(node.key)) return;
      if (chip == RoomsChip.all) {
        final m = match(node.name, query);
        if (m != null) hits.add(RoomsHit.space(node, path, m));
      }
      final inside = [...path, node.name];
      for (final room in node.rooms) {
        addRoom(room, inside);
      }
      for (final sub in node.subspaces) {
        walk(sub, inside);
      }
    }

    for (final room in standalone) {
      addRoom(room, const []);
    }
    if (chip != RoomsChip.standalone) {
      for (final space in spaces) {
        walk(space, const []);
      }
    }

    hits.sort((a, b) {
      final score = a.match.score.compareTo(b.match.score);
      if (score != 0) return score;
      if (a.isSpace != b.isSpace) return a.isSpace ? 1 : -1;
      if (!a.isSpace) {
        final time = facts
            .lastActivity(b.room as R)
            .compareTo(facts.lastActivity(a.room as R));
        if (time != 0) return time;
      }
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return hits;
  }

  /// How many hits each chip would show for [query], for the counts on the
  /// chips while searching.
  static Map<RoomsChip, int> searchCounts<S, R>(
          {required String query,
          required List<R> standalone,
          required List<SpaceNode<S, R>> spaces,
          required RoomFacts<R> facts,
          required Object Function(R room) identity}) =>
      {
        for (final chip in RoomsChip.values)
          chip: search(
                  query: query,
                  standalone: standalone,
                  spaces: spaces,
                  chip: chip,
                  facts: facts,
                  identity: identity)
              .length
      };

  /// Unread rooms in [section] and all its subsections.
  static int unreadIn<S, R>(RoomsSection<S, R> section, RoomFacts<R> facts) =>
      section.rooms.where(facts.unread).length +
      section.subsections.fold(0, (sum, s) => sum + unreadIn(s, facts));

  /// What a collapsed space says after its count: "2 subspaces · 3 unread".
  static String collapsedSummary<S, R>(RoomsSection<S, R> section, int unread) {
    final subspaces = section.subspaceCount;
    return [
      if (subspaces > 0) subspaces == 1 ? "1 subspace" : "$subspaces subspaces",
      if (unread > 0) "$unread unread",
    ].join(" · ");
  }

  /// Under a type chip: "Book Club and Gaming Guild have no voice rooms."
  static String withoutNote(List<String> spaces, RoomsChip chip) {
    final what = switch (chip) {
      RoomsChip.voice => "voice rooms",
      RoomsChip.photos => "photo albums",
      RoomsChip.calendars => "calendars",
      RoomsChip.unread => "unread rooms",
      _ => "rooms here",
    };
    final names = switch (spaces.length) {
      0 => "",
      1 => spaces.first,
      2 => "${spaces[0]} and ${spaces[1]}",
      _ => "${spaces.take(spaces.length - 1).join(", ")} and ${spaces.last}",
    };
    return spaces.length == 1
        ? "$names has no $what."
        : "$names have no $what.";
  }

  /// A chip's label; with the match count while searching.
  static String chipLabel(RoomsChip chip, int? count, {required bool phone}) {
    final label = phone ? chip.shortLabel : chip.label;
    return count == null ? label : "$label $count";
  }

  /// The rows a section shows before "Show N more": all of them when
  /// they're at most [limit] + 1 (a "Show 1 more" would save nothing).
  static int visibleRooms(int total, int limit, {required bool expanded}) {
    if (expanded || total <= limit + 1) return total;
    return limit;
  }
}

class RoomsTree<S, R> {
  RoomsTree(this.sections, this.without);
  final List<RoomsSection<S, R>> sections;

  /// Top-level spaces with nothing under the chip.
  final List<String> without;

  bool get isEmpty => sections.isEmpty;
}
