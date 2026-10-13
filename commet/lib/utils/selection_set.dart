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
  String? _dragLast;

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

  /// Starts a drag on [group]: it flips, and every row the drag then passes
  /// over takes the same state.
  void dragStart(List<String> group) {
    if (group.isEmpty) return;
    _dragValue = toggle(group);
    _dragLast = group.first;
  }

  /// The drag reached [group]. Rows skipped between two pointer samples are
  /// set too.
  void dragOver(List<String> ordered, List<String> group) {
    final value = _dragValue;
    if (value == null || group.isEmpty) return;
    final last = _dragLast;
    if (last != null) setAll(range(ordered, last, group.first), value);
    setAll(group, value);
    _dragLast = group.first;
    lastToggled = group.first;
  }

  void dragEnd() {
    _dragValue = null;
    _dragLast = null;
  }

  /// Ticked ids in [ordered]'s order; ticked ids missing from it are left out.
  List<String> inOrder(List<String> ordered) =>
      ordered.where(_ids.contains).toList();

  void clear() {
    _ids.clear();
    lastToggled = null;
    dragEnd();
  }

  /// How many of [items] pass [canDelete].
  static int deletableCount<T>(Iterable<T> items, bool Function(T) canDelete) =>
      items.where(canDelete).length;

  /// Text for "Copy": one `Sender: text` line per message, in the given order.
  static String copyText(Iterable<(String sender, String text)> messages) =>
      messages.map((m) => "${m.$1}: ${m.$2}").join("\n");
}
