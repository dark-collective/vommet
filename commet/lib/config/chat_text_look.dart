// Vommet issue 783: a 1:1 chat's own text color, font and size, picked in
// Room settings › Appearance. Local only: stored on this device, never sent
// to the room or to the other person (unlike the chat wallpaper). Only the
// message body text changes; links, mentions, code and names keep their
// own colors and fonts.
import 'dart:async';
import 'dart:convert';

import 'package:commet/client/matrix/components/chat_wallpaper/matrix_chat_wallpaper_component.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/client/room.dart';
import 'package:commet/config/app_font.dart';
import 'package:commet/config/preferences/string_preference.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class ChatTextLook {
  const ChatTextLook(
      {this.color, this.fontId = AppFont.defaultId, this.scale = 1});

  /// The body text color, or null for the theme's.
  final Color? color;

  /// A bundled font's id ([AppFont.bundled]), or [AppFont.defaultId] for the
  /// app font.
  final String fontId;

  /// Text size, [minScale] to [maxScale]; 1 is the app's size.
  final double scale;

  static const double minScale = 0.8;
  static const double maxScale = 1.5;

  /// Below this WCAG ratio the settings warn the text may be hard to read.
  static const double readableContrast = 4.5;

  static const ChatTextLook none = ChatTextLook();

  bool get isDefault =>
      color == null && fontId == AppFont.defaultId && scale == 1;

  /// The family to draw the body in, or null to keep the app font.
  String? get fontFamily => AppFont.bundledById(fontId)?.family;

  ChatTextLook copyWith(
          {Color? color,
          bool clearColor = false,
          String? fontId,
          double? scale}) =>
      ChatTextLook(
        color: clearColor ? null : color ?? this.color,
        fontId: fontId ?? this.fontId,
        scale: (scale ?? this.scale).clamp(minScale, maxScale),
      );

  Map<String, Object?> toJson() => {
        if (color != null) "color": color!.toARGB32(),
        if (fontId != AppFont.defaultId) "font": fontId,
        if (scale != 1) "scale": scale,
      };

  static ChatTextLook fromJson(Object? json) {
    if (json is! Map) return none;
    final color = json["color"];
    final font = json["font"];
    final scale = json["scale"];
    return ChatTextLook(
      color: color is int ? Color(color).withAlpha(0xFF) : null,
      fontId: font is String && AppFont.bundledById(font) != null
          ? font
          : AppFont.defaultId,
      scale: scale is num ? scale.toDouble().clamp(minScale, maxScale) : 1,
    );
  }

  /// The body's text style on top of [base] (its size scaled).
  TextStyle apply(TextStyle base) => base.copyWith(
        color: color,
        fontFamily: fontFamily,
        fontSize: base.fontSize == null ? null : base.fontSize! * scale,
      );

  /// WCAG contrast ratio of two colors, 1 (same) to 21. Translucent colors
  /// are judged on [over].
  static double contrast(Color a, Color b, {Color? over}) {
    if (over != null) {
      a = Color.alphaBlend(a, over);
      b = Color.alphaBlend(b, over);
    }
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    return la > lb ? (la + 0.05) / (lb + 0.05) : (lb + 0.05) / (la + 0.05);
  }

  /// The color nearest [color] (same hue, lighter or darker) that reads on
  /// [background]: for "Pick a readable color".
  static Color readableNear(Color color, Color background) {
    if (contrast(color, background) >= readableContrast) return color;
    final hsl = HSLColor.fromColor(color);
    final lighter = background.computeLuminance() < 0.5;
    for (var i = 1; i <= 20; i++) {
      final l = (hsl.lightness + (lighter ? 0.05 : -0.05) * i).clamp(0.0, 1.0);
      final c = hsl.withLightness(l).toColor();
      if (contrast(c, background) >= readableContrast) return c;
    }
    return lighter ? Colors.white : Colors.black;
  }

  /// Ready-made colors offered before "any color".
  static const presets = [
    Color(0xFFE53935),
    Color(0xFFFB8C00),
    Color(0xFFFDD835),
    Color(0xFF43A047),
    Color(0xFF00ACC1),
    Color(0xFF1E88E5),
    Color(0xFF8E24AA),
    Color(0xFFD81B60),
    Color(0xFFFFFFFF),
    Color(0xFF212121),
  ];

  @override
  bool operator ==(Object other) =>
      other is ChatTextLook &&
      other.color?.toARGB32() == color?.toARGB32() &&
      other.fontId == fontId &&
      other.scale == scale;

  @override
  int get hashCode => Object.hash(color?.toARGB32(), fontId, scale);
}

/// Every chat's look, by [Room.localId], as one JSON object.
final StringPreference chatTextLooksPreference =
    StringPreference("vommet_chat_text_looks", defaultValue: "{}");

class ChatTextLooks {
  /// Whether [room] can have its own look: 1:1 direct messages only.
  static bool availableIn(Room room) {
    if (room is! MatrixRoom || room.client is! MatrixClient) return false;
    return MatrixChatWallpaperComponent.isOneToOneRoom(
        room, room.client as MatrixClient);
  }

  static Map<String, Object?> _all() {
    try {
      final decoded = jsonDecode(chatTextLooksPreference.value);
      if (decoded is Map<String, Object?>) return decoded;
    } catch (_) {}
    return {};
  }

  static ChatTextLook of(String roomLocalId) =>
      ChatTextLook.fromJson(_all()[roomLocalId]);

  static Future<void> set(String roomLocalId, ChatTextLook look) async {
    final all = _all();
    if (look.isDefault) {
      all.remove(roomLocalId);
    } else {
      all[roomLocalId] = look.toJson();
    }
    await chatTextLooksPreference.set(jsonEncode(all));
  }
}

/// Gives the timeline below it the room's look, and follows changes.
class ChatTextLookScope extends StatefulWidget {
  const ChatTextLookScope({required this.room, required this.child, super.key});

  final Room room;
  final Widget child;

  /// The look for message bodies here; [ChatTextLook.none] outside a scope.
  static ChatTextLook of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<_ChatTextLookInherited>()
          ?.look ??
      ChatTextLook.none;

  @override
  State<ChatTextLookScope> createState() => _ChatTextLookScopeState();
}

class _ChatTextLookScopeState extends State<ChatTextLookScope> {
  late ChatTextLook look;
  StreamSubscription? sub;

  @override
  void initState() {
    super.initState();
    look = lookFor(widget.room);
    sub = chatTextLooksPreference.onChanged.listen((_) {
      final next = lookFor(widget.room);
      if (next != look && mounted) setState(() => look = next);
    });
  }

  @override
  void didUpdateWidget(covariant ChatTextLookScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.room != widget.room) look = lookFor(widget.room);
  }

  static ChatTextLook lookFor(Room room) => ChatTextLooks.availableIn(room)
      ? ChatTextLooks.of(room.localId)
      : ChatTextLook.none;

  @override
  void dispose() {
    sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _ChatTextLookInherited(look: look, child: widget.child);
}

class _ChatTextLookInherited extends InheritedWidget {
  const _ChatTextLookInherited({required this.look, required super.child});

  final ChatTextLook look;

  @override
  bool updateShouldNotify(_ChatTextLookInherited oldWidget) =>
      oldWidget.look != look;
}

String get chatTextLookTitle => Intl.message("Just for you",
    name: "chatTextLookTitle",
    desc: "Title of the room settings section with a chat's own text color, "
        "font and size, which only this person sees");

String get chatTextLookNote => Intl.message("Only on this device",
    name: "chatTextLookNote",
    desc: "Next to the 'Just for you' title: these text settings are stored "
        "on this device only and nobody else sees them");

String get chatTextLookColor => Intl.message("Text color",
    name: "chatTextLookColor",
    desc: "Label of the chat's own message text color");

String get chatTextLookDefaultColor => Intl.message("Default",
    name: "chatTextLookDefaultColor",
    desc: "The swatch that keeps the theme's message text color");

String get chatTextLookAnyColor => Intl.message("Any color",
    name: "chatTextLookAnyColor",
    desc: "Button that opens a picker for any message text color");

String get chatTextLookFont => Intl.message("Font",
    name: "chatTextLookFont", desc: "Label of the chat's own message font");

String get chatTextLookAppFont => Intl.message("App font",
    name: "chatTextLookAppFont",
    desc: "Font choice that keeps the font picked for the whole app");

String get chatTextLookSize => Intl.message("Text size",
    name: "chatTextLookSize", desc: "Label of the chat's own text size slider");

String get chatTextLookReset => Intl.message("Reset",
    name: "chatTextLookReset",
    desc: "Button that puts this chat's text color, font and size back to "
        "the defaults");

String get chatTextLookPreview => Intl.message("This is how messages look here",
    name: "chatTextLookPreview",
    desc: "Sample message shown with the chat's own text color, font and size");

String chatTextLookContrast(String ratio) =>
    Intl.message("Contrast $ratio:1 against the message background",
        args: [ratio],
        name: "chatTextLookContrast",
        desc: "How readable the picked text color is, as a WCAG contrast "
            "ratio, e.g. 7.2:1");

String get chatTextLookLowContrast =>
    Intl.message("This color may be hard to read on the message background.",
        name: "chatTextLookLowContrast",
        desc: "Warning shown when the picked text color has low contrast");

String get chatTextLookUseAnyway => Intl.message("Use anyway",
    name: "chatTextLookUseAnyway",
    desc: "Keeps a hard-to-read text color after the warning");

String get chatTextLookPickReadable => Intl.message("Pick a readable color",
    name: "chatTextLookPickReadable",
    desc: "Switches to the nearest readable text color after the low "
        "contrast warning");
