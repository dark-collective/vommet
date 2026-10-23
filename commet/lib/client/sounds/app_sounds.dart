import 'dart:convert';
import 'dart:io';

import 'package:commet/config/platform_utils.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/main.dart';
import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

enum SoundGroup {
  messages("Messages"),
  calls("Calls"),
  inCall("In a call");

  final String label;
  const SoundGroup(this.label);
}

/// Vommet: every sound the app plays. Each can be left at its default, set
/// to none, or set to an audio file the user picked (see [AppSounds]).
///
/// [asset] is the shipped sound (assets/sound/<asset>.ogg, and the same name
/// in android/app/src/main/res/raw for the sounds Android plays itself). An
/// event without one either shares another event's sound ([sameAs]) or is
/// silent until the user picks a file.
enum SoundEvent {
  message("New message", "Plays when a message notification arrives.",
      SoundGroup.messages,
      asset: "message"),
  mention(
      "Mention or reply",
      "Plays when a message mentions you or replies to you.",
      SoundGroup.messages),
  ringIncoming(
      "Incoming call", "Plays while someone is calling you.", SoundGroup.calls,
      asset: "ringtone_in"),
  ringOutgoing(
      "Calling someone", "Plays while your call is ringing.", SoundGroup.calls,
      asset: "ringtone_out"),
  callNotAnswered(
      "Call not answered",
      "Plays when a call you started ends before anyone answers.",
      SoundGroup.calls),
  selfJoin("You join", "Plays when you join a call.", SoundGroup.inCall,
      asset: "joined_call"),
  selfLeave("You leave", "Plays when you leave a call.", SoundGroup.inCall,
      asset: "left_call"),
  peerJoin("Someone joins", "Plays when someone joins a call you're in.",
      SoundGroup.inCall),
  peerLeave("Someone leaves", "Plays when someone leaves a call you're in.",
      SoundGroup.inCall),
  connectionLost("Connection lost",
      "Plays when a call drops or starts reconnecting.", SoundGroup.inCall),
  mute("Mute", "Plays when you mute your microphone.", SoundGroup.inCall,
      asset: "muted"),
  unmute("Unmute", "Plays when you unmute your microphone.", SoundGroup.inCall,
      asset: "unmuted"),
  deafen("Deafen", "Plays when you deafen.", SoundGroup.inCall),
  undeafen("Undeafen", "Plays when you undeafen.", SoundGroup.inCall),
  talkStart(
      "Push to talk on",
      "Plays when push to talk starts sending your microphone.",
      SoundGroup.inCall,
      asset: "ptt_start"),
  talkStop(
      "Push to talk off",
      "Plays when push to talk stops sending your microphone.",
      SoundGroup.inCall,
      asset: "ptt_stop"),
  screenShareStart(
      "Screen share starts",
      "Plays when you or someone in your call starts sharing a screen.",
      SoundGroup.inCall),
  screenShareStop("Screen share stops",
      "Plays when a screen share in your call ends.", SoundGroup.inCall);

  final String label;
  final String description;
  final SoundGroup group;
  final String? asset;

  const SoundEvent(this.label, this.description, this.group, {this.asset});

  /// Events that play another event's sound until the user changes them, so
  /// nothing sounds different from before. Connection lost and screen shares
  /// had no sound of their own, so they borrow the leave and join sounds.
  SoundEvent? get sameAs => switch (this) {
        mention => message,
        callNotAnswered => selfLeave,
        peerJoin => selfJoin,
        peerLeave => selfLeave,
        connectionLost => selfLeave,
        screenShareStart => peerJoin,
        screenShareStop => peerLeave,
        deafen => mute,
        undeafen => unmute,
        _ => null,
      };

  bool get hasDefault => asset != null || sameAs != null;

  /// Android plays these from a notification channel; the rest play in the
  /// app.
  bool get isAndroidChannelSound =>
      this == message || this == mention || this == ringIncoming;
}

enum SoundMode { standard, none, custom }

class SoundChoice {
  final SoundMode mode;

  /// A file path on desktop, a content:// URI on Android.
  final String? file;
  final String? name;

  const SoundChoice(this.mode, {this.file, this.name});

  static const standard = SoundChoice(SoundMode.standard);

  Map<String, dynamic> toJson() => {
        "mode": mode.name,
        if (file != null) "file": file,
        if (name != null) "name": name,
      };

  static SoundChoice fromJson(dynamic json) {
    if (json is! Map) return standard;
    final mode =
        SoundMode.values.where((m) => m.name == json["mode"]).firstOrNull ??
            SoundMode.standard;
    final file = json["file"] as String?;
    if (mode == SoundMode.custom && file == null) return standard;
    return SoundChoice(mode, file: file, name: json["name"] as String?);
  }
}

class AppSounds {
  static const MethodChannel _channel =
      MethodChannel("chat.commet.commetapp/utils");

  static Map<String, dynamic> _all() {
    try {
      final decoded = jsonDecode(preferences.soundChoices.value);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (e) {
      Log.w("Could not read sound settings: $e");
    }
    return {};
  }

  static SoundChoice choice(SoundEvent e) =>
      SoundChoice.fromJson(_all()[e.name]);

  /// What the settings show for [e]: "Default", "None", "Same as …" or the
  /// picked file's name.
  static String describe(SoundEvent e) {
    final c = choice(e);
    switch (c.mode) {
      case SoundMode.none:
        return "None";
      case SoundMode.custom:
        return c.name ?? p.basename(c.file!);
      case SoundMode.standard:
        if (e.asset != null) return "Default";
        if (e.sameAs != null) {
          return "Same as ${e.sameAs!.label.toLowerCase()}";
        }
        return "None";
    }
  }

  /// The sound to play for [e], or null for silence.
  static Media? media(SoundEvent e) => _media(source(e));

  static Media? defaultMedia(SoundEvent e) => _media(defaultSource(e));

  static Media? _media(String? uri) => uri == null ? null : Media(uri);

  /// The URI of the sound to play for [e], or null for silence.
  static String? source(SoundEvent e) {
    final c = choice(e);
    switch (c.mode) {
      case SoundMode.none:
        return null;
      case SoundMode.custom:
        if (PlatformUtils.isAndroid) return c.file!;
        if (File(c.file!).existsSync()) return Uri.file(c.file!).toString();
        Log.w("Sound file for ${e.name} is missing: ${c.file}");
        return defaultSource(e);
      case SoundMode.standard:
        return defaultSource(e);
    }
  }

  static String? defaultSource(SoundEvent e) {
    if (e.asset != null) return "asset:///assets/sound/${e.asset}.ogg";
    if (e.sameAs != null) return source(e.sameAs!);
    return null;
  }

  static Player? _player;

  /// Plays a one-off sound for [e] at the notification volume.
  static void play(SoundEvent e) {
    final sound = media(e);
    if (sound == null) return;
    try {
      _player ??= Player(configuration: PlayerConfiguration());
      _player!.setVolume(preferences.notificationsVolume.value);
      _player!.setPlaylistMode(PlaylistMode.none);
      _player!.open(sound);
    } catch (e, s) {
      Log.onError(e, s);
    }
  }

  // Android notification channels. A channel's sound is fixed when it is
  // created, so each sound gets its own channel id. The defaults keep the
  // ids upstream used, so existing installs keep their channel settings.

  static String androidChannelId(SoundEvent e) {
    final c = choice(e);
    switch (e) {
      case SoundEvent.mention:
        if (c.mode == SoundMode.standard) {
          return androidChannelId(SoundEvent.message);
        }
        return "mentions_${_hash(c)}";
      case SoundEvent.ringIncoming:
        if (c.mode == SoundMode.standard) return "incoming_calls_channel_1";
        return "incoming_calls_${_hash(c)}";
      default:
        if (c.mode == SoundMode.standard) return "messages";
        return "messages_${_hash(c)}";
    }
  }

  static String _hash(SoundChoice c) => sha1
      .convert(utf8.encode(jsonEncode(c.toJson())))
      .toString()
      .substring(0, 10);

  /// The sound for a channel-backed event, or null for a silent channel.
  static AndroidNotificationSound? androidSound(SoundEvent e) {
    final c = choice(e);
    switch (c.mode) {
      case SoundMode.none:
        return null;
      case SoundMode.custom:
        return UriAndroidNotificationSound(c.file!);
      case SoundMode.standard:
        if (e.asset != null)
          return RawResourceAndroidNotificationSound(e.asset);
        if (e.sameAs != null) return androidSound(e.sameAs!);
        return null;
    }
  }

  static AndroidNotificationChannel androidChannel(SoundEvent e) {
    // An unchanged mention sound uses the message channel as it is.
    if (e == SoundEvent.mention && choice(e).mode == SoundMode.standard) {
      return androidChannel(SoundEvent.message);
    }
    final sound = androidSound(e);
    final name = switch (e) {
      SoundEvent.mention => "Mentions and replies",
      SoundEvent.ringIncoming => "Incoming Call",
      _ => "Message Received",
    };
    return AndroidNotificationChannel(androidChannelId(e), name,
        importance: Importance.high, playSound: sound != null, sound: sound);
  }

  /// Makes the channels for the current sounds and deletes the ones made
  /// for sounds no longer chosen.
  static Future<void> refreshAndroidChannels() async {
    if (!PlatformUtils.isAndroid) return;
    final android = FlutterLocalNotificationsPlugin()
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return;

    final events = SoundEvent.values.where((e) => e.isAndroidChannelSound);
    final active = {for (final e in events) androidChannelId(e)};
    for (final id in active) {
      final e = events.firstWhere((e) => androidChannelId(e) == id);
      await android.createNotificationChannel(androidChannel(e));
    }
    for (final c in await android.getNotificationChannels() ?? []) {
      final ours = c.id == "messages" ||
          c.id.startsWith("messages_") ||
          c.id.startsWith("mentions_") ||
          c.id == "incoming_calls_channel_1" ||
          c.id.startsWith("incoming_calls_");
      if (ours && !active.contains(c.id)) {
        await android.deleteNotificationChannel(c.id);
      }
    }
  }

  // Changing sounds.

  static Future<void> _set(SoundEvent e, SoundChoice c) async {
    final old = choice(e);
    final all = _all();
    if (c.mode == SoundMode.standard) {
      all.remove(e.name);
    } else {
      all[e.name] = c.toJson();
    }
    await preferences.soundChoices.set(jsonEncode(all));
    if (old.mode == SoundMode.custom && old.file != c.file) {
      await _deleteFile(old.file!);
    }
    if (e.isAndroidChannelSound) await refreshAndroidChannels();
  }

  static Future<void> setDefault(SoundEvent e) => _set(e, SoundChoice.standard);

  static Future<void> setNone(SoundEvent e) =>
      _set(e, const SoundChoice(SoundMode.none));

  /// Lets the user pick an audio file for [e]. Returns false if they
  /// cancelled. Throws [UnsupportedError] on Android before 10, where a file
  /// can't be handed to the notification system without storage permission.
  static Future<bool> pickFile(SoundEvent e) async {
    final result = await FilePicker.platform
        .pickFiles(type: FileType.audio, allowMultiple: false);
    final picked = result?.files.firstOrNull;
    if (picked?.path == null) return false;

    String stored;
    if (PlatformUtils.isAndroid) {
      try {
        stored = (await _channel.invokeMethod<String>("importNotificationSound",
            {"path": picked!.path, "name": picked.name}))!;
      } on PlatformException catch (err) {
        if (err.code == "UNSUPPORTED") {
          throw UnsupportedError("Custom sounds need Android 10 or newer");
        }
        rethrow;
      }
    } else {
      // A copy, so the sound keeps working if the original moves.
      final dir = Directory(
          p.join((await getApplicationSupportDirectory()).path, "sounds"));
      await dir.create(recursive: true);
      stored = p.join(dir.path,
          "${e.name}-${DateTime.now().millisecondsSinceEpoch}${p.extension(picked!.path!)}");
      await File(picked.path!).copy(stored);
    }

    await _set(
        e, SoundChoice(SoundMode.custom, file: stored, name: picked.name));
    return true;
  }

  static Future<void> _deleteFile(String stored) async {
    try {
      if (PlatformUtils.isAndroid) {
        await _channel.invokeMethod("deleteNotificationSound", {"uri": stored});
      } else {
        final f = File(stored);
        if (await f.exists()) await f.delete();
      }
    } catch (e) {
      Log.w("Could not delete an old sound file: $e");
    }
  }
}
