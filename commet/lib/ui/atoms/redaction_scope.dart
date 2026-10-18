// Vommet: redacted mode in the widget tree (Vommet issue 400).
//
// [GlobalRedactionScope] sits above the app and provides the policy from the
// settings. Widgets that show names, avatars, message text, room names or
// pictures ask `RedactionScope.of(context)` and pass what they show through
// it. A [RedactionScope] placed lower down overrides the settings for its
// subtree only, e.g. to render a redacted copy of a view for a screenshot
// (Vommet issue 403) while the app itself stays as it is.

import 'dart:async';
import 'dart:ui';

import 'package:commet/client/components/direct_messages/direct_message_component.dart';
import 'package:commet/client/room.dart';
import 'package:commet/main.dart';
import 'package:commet/utils/redaction/redaction_policy.dart';
import 'package:commet/utils/redaction/redaction_preferences.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class RedactionScope extends InheritedWidget {
  const RedactionScope({super.key, required this.policy, required super.child});

  /// Redacts [child] with [settings], whatever the app-wide settings are.
  RedactionScope.withSettings(
      {super.key, required RedactionSettings settings, required super.child})
      : policy = RedactionPolicy(settings);

  final RedactionPolicy policy;

  /// The policy for [context]; [RedactionPolicy.off] outside any scope.
  static RedactionPolicy of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<RedactionScope>()?.policy ??
      RedactionPolicy.off;

  @override
  bool updateShouldNotify(RedactionScope oldWidget) =>
      oldWidget.policy.settings != policy.settings;
}

/// Provides the app-wide policy from the settings, rebuilding when they
/// change, and hides avatars app-wide through tiamat's [tiamat.Avatar].
class GlobalRedactionScope extends StatefulWidget {
  const GlobalRedactionScope({super.key, required this.child});

  final Widget child;

  @override
  State<GlobalRedactionScope> createState() => _GlobalRedactionScopeState();
}

class _GlobalRedactionScopeState extends State<GlobalRedactionScope> {
  late RedactionPolicy policy;
  StreamSubscription? subscription;

  @override
  void initState() {
    super.initState();
    tiamat.Avatar.redactor = redactAvatar;
    policy = RedactionPolicy(preferences.effectiveRedaction);
    subscription = preferences.onSettingChanged.listen((_) {
      final settings = preferences.effectiveRedaction;
      if (settings != policy.settings) {
        setState(() => policy = RedactionPolicy(settings));
      }
    });
  }

  @override
  void dispose() {
    subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      RedactionScope(policy: policy, child: widget.child);
}

/// [tiamat.Avatar.redactor]: while avatars are hidden, every avatar becomes a
/// placeholder in the colour (and with the letter) of whoever it shows.
tiamat.Avatar? redactAvatar(BuildContext context, tiamat.Avatar avatar) {
  final policy = RedactionScope.of(context);
  if (!policy.hidesAvatars) return null;
  final key = avatar.redactionKey ?? avatar.placeholderText ?? "";
  return avatar.redactedCopy(
      placeholderText: policy.avatarLetter(key),
      placeholderColor: policy.identityColor(key));
}

extension RoomRedaction on RedactionPolicy {
  /// [room]'s name; a direct message follows the name switch.
  String roomDisplayName(Room room, {String? name}) {
    if (!isActive) return name ?? room.displayName;
    final dms = room.client.getComponent<DirectMessagesComponent>();
    final partner = dms?.isRoomDirectMessage(room) == true
        ? dms!.getDirectMessagePartnerId(room)
        : null;
    return roomName(name ?? room.displayName, room.identifier,
        dmPartnerId: partner);
  }

  /// A room topic, hidden along with room names or message text.
  String? roomTopic(String? topic) =>
      settings.roomNames || redactsText ? null : topic;

  /// The redaction key for [room]'s avatar: the person in a direct message,
  /// otherwise the room.
  String roomAvatarKey(Room room) {
    final dms = room.client.getComponent<DirectMessagesComponent>();
    if (dms?.isRoomDirectMessage(room) == true) {
      return dms!.getDirectMessagePartnerId(room) ?? room.identifier;
    }
    return room.identifier;
  }

  /// [style] for text that went through [RedactionPolicy.text]: with text
  /// hidden it is drawn as solid bars in [color], the glyphs invisible.
  TextStyle? redactedTextStyle(TextStyle? style, Color color) {
    if (!drawsTextAsBars) return style;
    return (style ?? const TextStyle())
        .copyWith(color: const Color(0x00000000), backgroundColor: color);
  }
}

/// Message text: [text] as a [Text], redacted per the scope's policy.
class RedactedText extends StatelessWidget {
  const RedactedText(this.text,
      {super.key, this.style, this.maxLines, this.overflow});

  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) {
    final policy = RedactionScope.of(context);
    final barColor = Theme.of(context).colorScheme.onSurface.withAlpha(90);
    return Text(policy.text(text),
        maxLines: maxLines,
        overflow: overflow,
        style: policy.redactedTextStyle(style, barColor));
  }
}

/// A picture or video in a chat; blurred when the scope blurs images.
class RedactedImage extends StatelessWidget {
  const RedactedImage({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!RedactionScope.of(context).blursImages) return child;
    return ClipRect(
      child: ImageFiltered(
        imageFilter:
            ImageFilter.blur(sigmaX: 24, sigmaY: 24, tileMode: TileMode.decal),
        child: child,
      ),
    );
  }
}
