import 'package:commet/main.dart';
import 'package:commet/utils/media_auto_download.dart';
import 'package:flutter/widgets.dart';

/// Vommet: whether a video event's `info` marks it as a GIF. mautrix bridges
/// (Telegram, WhatsApp, Discord, ...) send GIFs as short silent MP4s with
/// `fi.mau.gif` / `fi.mau.loop` set.
bool isGifVideoInfo(Map<String, Object?> info) =>
    info["fi.mau.gif"] == true || info["fi.mau.loop"] == true;

/// Vommet: whether GIFs should play by themselves here: the Autoplay GIFs
/// setting is on, the device isn't asking for reduced motion, and the
/// current network's automatic download choices allow GIFs.
bool shouldAutoplayGifs(BuildContext context) =>
    preferences.autoplayGifs.value &&
    !(MediaQuery.maybeDisableAnimationsOf(context) ?? false) &&
    MediaAutoDownload.allowsNow(AutoMediaKind.gif);
