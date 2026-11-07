import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import 'package:commet/client/room.dart';

/// An entry in the desktop browser-style room navigation history stack
/// (Vommet issue 1207).
class DesktopRoomHistoryEntry {
  DesktopRoomHistoryEntry({
    required this.roomId,
    required this.clientId,
    this.spaceId,
    this.showAsTextRoom = false,
  });

  final String roomId;
  final String clientId;
  final String? spaceId;
  final bool showAsTextRoom;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DesktopRoomHistoryEntry &&
          runtimeType == other.runtimeType &&
          roomId == other.roomId &&
          clientId == other.clientId &&
          spaceId == other.spaceId &&
          showAsTextRoom == other.showAsTextRoom;

  @override
  int get hashCode => Object.hash(roomId, clientId, spaceId, showAsTextRoom);

  @override
  String toString() =>
      'DesktopRoomHistoryEntry(roomId: $roomId, clientId: $clientId, spaceId: $spaceId, showAsTextRoom: $showAsTextRoom)';
}

/// Browser-style back/forward history for rooms and chats opened on desktop
/// (Vommet issue 1207).
class DesktopRoomHistory {
  DesktopRoomHistory({this.maxEntries = 100});

  final int maxEntries;
  final List<DesktopRoomHistoryEntry> _entries = [];
  int _index = -1;

  int get length => _entries.length;
  int get currentIndex => _index;
  List<DesktopRoomHistoryEntry> get entries => List.unmodifiable(_entries);

  DesktopRoomHistoryEntry? get currentEntry =>
      _index >= 0 && _index < _entries.length ? _entries[_index] : null;

  /// Records a room into the history stack.
  ///
  /// If the recorded room matches the current entry, its view mode and space
  /// are updated in place without creating a duplicate entry.
  /// Any forward history ahead of the current entry is cleared.
  void record(
    Room room, {
    String? spaceId,
    bool showAsTextRoom = false,
  }) {
    final roomId = room.identifier;
    final clientId = room.client.identifier;

    // Consecutive duplicate room: update in place without pushing.
    if (_index >= 0 &&
        _index < _entries.length &&
        _entries[_index].roomId == roomId &&
        _entries[_index].clientId == clientId) {
      if (_entries[_index].showAsTextRoom != showAsTextRoom ||
          _entries[_index].spaceId != spaceId) {
        _entries[_index] = DesktopRoomHistoryEntry(
          roomId: roomId,
          clientId: clientId,
          spaceId: spaceId,
          showAsTextRoom: showAsTextRoom,
        );
      }
      return;
    }

    // Discard any forward history beyond current position.
    if (_index >= 0 && _index < _entries.length - 1) {
      _entries.removeRange(_index + 1, _entries.length);
    }

    _entries.add(DesktopRoomHistoryEntry(
      roomId: roomId,
      clientId: clientId,
      spaceId: spaceId,
      showAsTextRoom: showAsTextRoom,
    ));
    _index = _entries.length - 1;

    // Bound memory usage.
    if (_entries.length > maxEntries) {
      _entries.removeAt(0);
      _index--;
    }
  }

  /// Whether there is a previous valid room in history.
  bool canGoBack({
    bool Function(DesktopRoomHistoryEntry entry)? isValid,
    bool isCurrentRoomNull = false,
  }) {
    if (_entries.isEmpty) return false;
    final startIndex = isCurrentRoomNull ? _index : _index - 1;
    for (var i = startIndex; i >= 0 && i < _entries.length; i--) {
      if (isValid == null || isValid(_entries[i])) return true;
    }
    return false;
  }

  /// Whether there is a forward valid room in history.
  bool canGoForward({
    bool Function(DesktopRoomHistoryEntry entry)? isValid,
  }) {
    if (_entries.isEmpty || _index >= _entries.length - 1) return false;
    for (var i = _index + 1; i < _entries.length; i++) {
      if (isValid == null || isValid(_entries[i])) return true;
    }
    return false;
  }

  /// Moves back in history, skipping and pruning any entries that fail [isValid].
  ///
  /// If [isCurrentRoomNull] is true (e.g. the room was closed to show a space
  /// overview or home screen), the current history entry is reopened first
  /// before traversing to earlier entries.
  DesktopRoomHistoryEntry? goBack({
    bool Function(DesktopRoomHistoryEntry entry)? isValid,
    bool isCurrentRoomNull = false,
  }) {
    var targetIndex = isCurrentRoomNull ? _index : _index - 1;
    while (targetIndex >= 0) {
      final entry = _entries[targetIndex];
      if (isValid == null || isValid(entry)) {
        _index = targetIndex;
        return entry;
      }
      _entries.removeAt(targetIndex);
      _index--;
      targetIndex--;
    }
    return null;
  }

  /// Moves forward in history, skipping and pruning any entries that fail [isValid].
  DesktopRoomHistoryEntry? goForward({
    bool Function(DesktopRoomHistoryEntry entry)? isValid,
  }) {
    if (_entries.isEmpty || _index >= _entries.length - 1) return null;

    while (_index + 1 < _entries.length) {
      final targetIndex = _index + 1;
      final entry = _entries[targetIndex];
      if (isValid == null || isValid(entry)) {
        _index = targetIndex;
        return entry;
      }
      // Invalid entry: prune. Next candidate shifts into targetIndex.
      _entries.removeAt(targetIndex);
    }
    return null;
  }

  /// Prunes any entries matching [roomId] (and optionally [clientId]).
  void onRoomRemoved(String roomId, [String? clientId]) {
    for (var i = _entries.length - 1; i >= 0; i--) {
      final entry = _entries[i];
      if (entry.roomId == roomId &&
          (clientId == null || entry.clientId == clientId)) {
        _entries.removeAt(i);
        if (i <= _index) _index--;
      }
    }
    if (_entries.isEmpty) _index = -1;
  }

  /// Prunes any entries whose client is not in [activeClientIds].
  void pruneClients(Set<String> activeClientIds) {
    for (var i = _entries.length - 1; i >= 0; i--) {
      if (!activeClientIds.contains(_entries[i].clientId)) {
        _entries.removeAt(i);
        if (i <= _index) _index--;
      }
    }
    if (_entries.isEmpty) _index = -1;
  }

  /// Clears the history stack.
  void clear() {
    _entries.clear();
    _index = -1;
  }
}

/// A host widget that listens for mouse side buttons (back and forward)
/// and invokes the corresponding history navigation callbacks
/// (Vommet issue 1207).
class DesktopRoomHistoryHost extends StatelessWidget {
  const DesktopRoomHistoryHost({
    super.key,
    required this.onNavigateBack,
    required this.onNavigateForward,
    required this.child,
  });

  final bool Function() onNavigateBack;
  final bool Function() onNavigateForward;
  final Widget child;

  static bool handlePointerDown(
    PointerDownEvent event, {
    required bool Function() onNavigateBack,
    required bool Function() onNavigateForward,
  }) {
    if (event.kind != PointerDeviceKind.mouse) return false;
    if (event.buttons == kBackMouseButton) {
      return onNavigateBack();
    } else if (event.buttons == kForwardMouseButton) {
      return onNavigateForward();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) => handlePointerDown(
        event,
        onNavigateBack: onNavigateBack,
        onNavigateForward: onNavigateForward,
      ),
      child: child,
    );
  }
}
