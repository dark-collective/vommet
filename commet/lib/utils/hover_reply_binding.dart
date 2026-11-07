// Vommet issue 1069: one local Reply binding; never registered with the OS.
import 'dart:convert';

import 'package:commet/main.dart';
import 'package:commet/utils/system_wide_shortcuts/system_wide_shortcuts.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:intl/intl.dart';

class HoverReplyBinding {
  HoverReplyBinding(this.key, this.physical, this.modifiers);
  final LogicalKeyboardKey key;
  final PhysicalKeyboardKey physical;
  final Set<HotKeyModifier> modifiers;

  static int _captures = 0;
  static bool get capturing => _captures > 0;
  static Future<T> capture<T>(Future<T> Function() body) async {
    _captures++;
    try {
      return await body();
    } finally {
      _captures--;
    }
  }

  static Set<HotKeyModifier> get pressed =>
      HotKeyModifier.values.where((m) => m.isModifierPressed).toSet();
  static HoverReplyBinding fromEvent(KeyEvent event) =>
      HoverReplyBinding(event.logicalKey, event.physicalKey, pressed);

  static HoverReplyBinding? get saved {
    try {
      final value = preferences.hoverReplyKey.value;
      if (value == null) return null;
      final data = jsonDecode(value) as Map<String, dynamic>;
      return HoverReplyBinding(
          LogicalKeyboardKey(data['key'] as int),
          PhysicalKeyboardKey(data['physical'] as int),
          (data['modifiers'] as List)
              .map((i) => HotKeyModifier.values[i as int])
              .toSet());
    } catch (_) {
      return null;
    }
  }

  Future<void> save() async {
    if (invalidReason != null) return;
    await preferences.hoverReplyKey.set(jsonEncode({
      'key': key.keyId,
      'physical': physical.usbHidUsage,
      'modifiers': modifiers.map((m) => m.index).toList(),
    }));
  }

  String get label => [
        if (modifiers.contains(HotKeyModifier.control))
          Intl.message('Ctrl',
              name: 'hoverReplyControl', desc: 'Control key label'),
        if (modifiers.contains(HotKeyModifier.meta))
          Intl.message('Meta', name: 'hoverReplyMeta', desc: 'Meta key label'),
        if (modifiers.contains(HotKeyModifier.shift))
          Intl.message('Shift',
              name: 'hoverReplyShift', desc: 'Shift key label'),
        key.keyLabel,
      ].join(' + ');

  bool overlaps(HotKey other) {
    if (!setEquals(modifiers, (other.modifiers ?? []).toSet())) return false;
    return other.physicalKey == physical ||
        other.logicalKey == key ||
        HardwareKeyboard.instance.lookUpLayout(other.physicalKey) == key;
  }

  static bool conflictsWithReply(HotKey key) => saved?.overlaps(key) == true;
  bool matches(KeyEvent event) =>
      event.logicalKey == key && setEquals(pressed, modifiers);

  String? get invalidReason {
    final function = key.keyId >= LogicalKeyboardKey.f1.keyId &&
        key.keyId <= LogicalKeyboardKey.f12.keyId;
    final letter = RegExp(r'^[A-Z]$').hasMatch(key.keyLabel);
    final modified = modifiers.contains(HotKeyModifier.control) ||
        modifiers.contains(HotKeyModifier.meta);
    // A bounded allow list leaves editing, navigation, AltGr and app keys alone.
    const reserved = {'A', 'B', 'C', 'F', 'G', 'H', 'K', 'V', 'X', 'Y', 'Z'};
    if (modifiers.any((m) =>
            m != HotKeyModifier.control &&
            m != HotKeyModifier.meta &&
            m != HotKeyModifier.shift) ||
        (!function &&
            !(letter && modified && !reserved.contains(key.keyLabel))) ||
        key == LogicalKeyboardKey.f11 ||
        (kIsWeb && (!function || !modified))) return unsupported;
    for (final entry in SystemWideShortcuts.shortcuts.entries) {
      final callKey =
          entry.value.hotkey ?? preferences.getSystemHotkey(entry.key);
      if (callKey != null && overlaps(callKey)) return callConflict;
    }
    return null;
  }

  static String get title => Intl.message('Reply to message under pointer',
      name: 'hoverReplyTitle', desc: 'Local message reply shortcut setting');
  static String get unsupported => kIsWeb
      ? Intl.message(
          'Choose a Ctrl or Meta function-key combination. Browser shortcuts are reserved.',
          name: 'hoverReplyWebUnsupported',
          desc: 'Invalid browser reply shortcut reason')
      : Intl.message(
          'Choose a function key or a Ctrl or Meta letter combination that is not reserved for editing or navigation.',
          name: 'hoverReplyUnsupported',
          desc: 'Invalid reply shortcut reason');
  static String get callConflict =>
      Intl.message('This key is used by a call shortcut. Choose another key.',
          name: 'hoverReplyCallConflict',
          desc: 'Reply shortcut conflicts with a call shortcut');
  static String get replyConflict => Intl.message(
      'This key is used by Reply to message under pointer. Choose another key.',
      name: 'hoverReplyReverseConflict',
      desc: 'Call shortcut conflicts with the local reply shortcut');
}
