/// Vommet: the pure logic behind selecting several messages, kept free of
/// Flutter so it can be unit-tested.
///
/// Ids are event ids. A "group" is the ids one timeline row stands for: one
/// event, or several when a row draws several events (a media mosaic). Lists
/// called `ordered` hold the ids of the rows that can be ticked, in the order
/// the timeline lists them.
class SelectionSet {
  final Set<String> _ids = {};

  /// The id last ticked or unticked by a tap; Shift+click ranges start here.
  String? lastToggled;

  bool? _dragValue;
  List<String>? _dragStartGroup;
  Set<String>? _beforeDrag;

  int get length => _ids.length;
  bool get isEmpty => _ids.isEmpty;
  bool get isNotEmpty => _ids.isNotEmpty;
  Iterable<String> get ids => _ids;

  bool contains(String id) => _ids.contains(id);

  /// A group counts as ticked when all of it is.
  bool containsAll(Iterable<String> group) =>
      group.isNotEmpty && group.every(_ids.contains);

  void setAll(Iterable<String> group, bool value) {
    if (value) {
      _ids.addAll(group);
    } else {
      _ids.removeAll(group);
    }
  }

  void remove(String id) => _ids.remove(id);

  /// Ticks [group] unless all of it is ticked, in which case unticks it.
  /// Returns the new state.
  bool toggle(List<String> group) {
    if (group.isEmpty) return false;
    final value = !containsAll(group);
    setAll(group, value);
    lastToggled = group.first;
    return value;
  }

  /// The ids from [a] to [b] inclusive, in [ordered]'s order whichever comes
  /// first. Empty when either is missing from [ordered].
  static List<String> range(List<String> ordered, String a, String b) {
    final i = ordered.indexOf(a);
    final j = ordered.indexOf(b);
    if (i == -1 || j == -1) return const [];
    return ordered.sublist(i < j ? i : j, (i < j ? j : i) + 1);
  }

  /// Shift+click: ticks everything between the last toggled row and [group].
  /// Without a usable last toggled row it toggles [group] alone.
  void tickRange(List<String> ordered, List<String> group) {
    if (group.isEmpty) return;
    final from = lastToggled;
    final between =
        from == null ? const <String>[] : range(ordered, from, group.first);
    if (between.isEmpty) {
      toggle(group);
      return;
    }
    setAll(between, true);
    setAll(group, true);
    lastToggled = group.first;
  }

  bool get dragging => _dragValue != null;

  /// Starts a drag on [group]: it flips, and every row between it and the
  /// pointer then takes the same state.
  void dragStart(List<String> group) {
    if (group.isEmpty) return;
    _beforeDrag = {..._ids};
    _dragValue = toggle(group);
    _dragStartGroup = group;
  }

  /// The drag reached [group]. The selection follows the pointer, like
  /// Telegram: the rows from the start to [group] take the drag's state, and
  /// rows the drag moved back off get their state from before the drag.
  void dragOver(List<String> ordered, List<String> group) {
    final value = _dragValue;
    final start = _dragStartGroup;
    final before = _beforeDrag;
    if (value == null || start == null || before == null || group.isEmpty) {
      return;
    }
    _ids
      ..clear()
      ..addAll(before);
    setAll(range(ordered, start.first, group.first), value);
    setAll(start, value);
    setAll(group, value);
    lastToggled = group.first;
  }

  void dragEnd() {
    _dragValue = null;
    _dragStartGroup = null;
    _beforeDrag = null;
  }

  /// Ticked ids in [ordered]'s order; ticked ids missing from it are left out.
  List<String> inOrder(List<String> ordered) =>
      ordered.where(_ids.contains).toList();

  void clear() {
    _ids.clear();
    lastToggled = null;
    dragEnd();
  }

  /// How far a drag held at [y] scrolls a viewport spanning [top]..[bottom]
  /// per tick: positive towards the content above, negative towards the
  /// content below, 0 unless [y] is within [edge] of an edge. Faster the
  /// further past the edge, up to half of [edge].
  static double edgeScroll(double y, double top, double bottom, double edge) {
    if (y < top + edge) {
      return (top + edge - y).clamp(0, edge * 2) / 4;
    }
    if (y > bottom - edge) {
      return -(y - (bottom - edge)).clamp(0, edge * 2) / 4;
    }
    return 0;
  }

  /// How many of [items] pass [canDelete].
  static int deletableCount<T>(Iterable<T> items, bool Function(T) canDelete) =>
      items.where(canDelete).length;

  /// Text for "Copy": one `Sender: text` line per message, in the given order.
  static String copyText(Iterable<(String sender, String text)> messages) =>
      messages.map((m) => "${m.$1}: ${m.$2}").join("\n");
}
