import 'package:media_kit/media_kit.dart';

/// Sets the mpv property [name] on [platform].
Future<void> setMpvProperty(NativePlayer platform, String name, String value) =>
    platform.setProperty(name, value);
