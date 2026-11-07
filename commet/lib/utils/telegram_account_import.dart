import 'dart:async';
import 'dart:io' show Platform;

import 'package:commet/config/build_config.dart';
import 'package:commet/config/platform_utils.dart';
import 'package:commet/config/preferences/bool_preference.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/rust/api/telegram_import.dart';
import 'package:commet/rust/frb_generated.dart';
import 'package:flutter/services.dart';

/// Vommet issue 801: list the sticker and custom emoji packs of the user's
/// Telegram account. Vommet signs in by QR code (read-only, only the calls
/// in rust/telegram's allowlist), signs out straight away, and saves
/// nothing; the pack names then go into the normal multi-link import.
/// Off by default (an opt-in experiment).
final BoolPreference experimentTelegramAccountImport = BoolPreference(
    "vommet_experiment_telegram_account_import",
    defaultValue: false);

class TelegramAccountImport {
  /// Vommet's app id and hash from my.telegram.org, passed at build time
  /// (`--dart-define`) so they aren't in the repo and forks use their own.
  static const _apiId = int.fromEnvironment("VOMMET_TELEGRAM_API_ID");
  static const _apiHash = String.fromEnvironment("VOMMET_TELEGRAM_API_HASH");

  /// This build can do it: a platform that loads rust_lib_commet (not iOS
  /// or the web yet), with an app id built in.
  static bool get supported =>
      (PlatformUtils.isLinux ||
          PlatformUtils.isWindows ||
          (!PlatformUtils.isWeb && Platform.isMacOS) ||
          PlatformUtils.isAndroid) &&
      _apiId != 0 &&
      _apiHash.isNotEmpty;

  /// Show "Import all packs from your Telegram account".
  static bool get available =>
      supported && experimentTelegramAccountImport.value;

  static int _nextJob = 0;
  static Future<void>? _loadingNative;

  TelegramAccountImport();

  final int _job = _nextJob++;
  bool _started = false;

  /// Starts the login. The stream ends once the Telegram session is gone.
  Stream<TelegramImportEvent> start() async* {
    assert(!_started);
    _started = true;
    if (!RustLib.instance.initialized) {
      // A failed load throws into this import; let the next one retry.
      await (_loadingNative ??=
          RustLib.init().whenComplete(() => _loadingNative = null));
    }
    yield* telegramImportRun(
      job: _job,
      apiId: _apiId,
      apiHash: _apiHash,
      appVersion: BuildConfig.VERSION_TAG,
      systemVersion: Platform.operatingSystemVersion,
      langCode: Platform.localeName.split(RegExp("[_.-]")).first,
    );
  }

  void password(String password) =>
      telegramImportPassword(job: _job, password: password);

  void retrySignOut() => telegramImportRetrySignOut(job: _job);

  /// Stops; signs out first if the account might be signed in. Also ends
  /// the session after an unconfirmed sign-out.
  void cancel() {
    if (_started) telegramImportCancel(job: _job);
  }

  /// The t.me link the pack importer takes for [pack].
  static String linkFor(TelegramPack pack) => pack.emoji
      ? "https://t.me/addemoji/${pack.shortName}"
      : "https://t.me/addstickers/${pack.shortName}";

  static const _channel = MethodChannel("im.nether.chat/telegram_login");

  /// Android: an official Telegram app is installed, so the login link can
  /// go straight to it.
  static Future<bool> canOpenTelegramApp() async {
    if (!PlatformUtils.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>("isInstalled") ?? false;
    } catch (e) {
      Log.w("Couldn't check for the Telegram app: $e");
      return false;
    }
  }

  /// Android: hands [url] to an official Telegram app only, never to
  /// whichever app claims tg:// links. False when none could open it.
  static Future<bool> openInTelegramApp(String url) async {
    if (!PlatformUtils.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>("openLogin", {"url": url}) ??
          false;
    } catch (e) {
      Log.w("Couldn't open the Telegram app: $e");
      return false;
    }
  }
}
