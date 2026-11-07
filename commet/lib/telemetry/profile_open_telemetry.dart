// Vommet (schema v35): how long an opened user profile took to show and to
// fill in, as the opt-in diagnostics event "profile_open". One event per
// opened profile card, sent once everything it loads has arrived (or failed)
// or when it is closed, whichever comes first. Times are ms from the tap;
// flags say what was known beforehand and what the profile has. Never which
// user, server, image or room.

import 'package:commet/telemetry/telemetry.dart';

class ProfileOpenRecord {
  ProfileOpenRecord({required this.ownServer, int Function()? clock})
      : _clock = clock ?? _stopwatchClock();

  final int Function() _clock;

  static int Function() _stopwatchClock() {
    final watch = Stopwatch()..start();
    return () => watch.elapsedMilliseconds;
  }

  /// The user is on this account's homeserver.
  final bool ownServer;

  /// Something about the user was known before the server answered
  /// (an earlier lookup or a member event).
  bool cached = false;
  int? shownMs;

  int? fetchMs;
  int? profileMs;
  int? presenceMs;
  Object? fetchError;
  bool fetchDone = false;

  /// profile (the user's own color choice), memory (worked out earlier this
  /// run), banner, avatar or default (no picture, or it failed).
  String? colorSource;
  int? colorMs;

  /// The colors arrived after the card was already showing.
  bool colorLate = false;
  bool colorDone = false;

  int? timezoneInitMs;

  bool hasBanner = false;
  bool hasAvatar = false;
  bool hasTimezone = false;
  int? bannerMs;
  int? bannerFullMs;
  bool bannerFailed = false;
  int? avatarMs;
  int? avatarFullMs;
  bool avatarFailed = false;

  bool _recorded = false;
  bool get recorded => _recorded;

  int now() => _clock();

  bool get _bannerSettled => !hasBanner || bannerFailed || bannerFullMs != null;
  bool get _avatarSettled => !hasAvatar || avatarFailed || avatarFullMs != null;

  bool get settled =>
      shownMs != null &&
      fetchDone &&
      colorDone &&
      _bannerSettled &&
      _avatarSettled;

  /// Sends the event when everything has arrived.
  void finishIfSettled() {
    if (settled) record(closedEarly: false);
  }

  /// Sends the event now (the card was closed).
  void close() => record(closedEarly: !settled);

  void record({required bool closedEarly}) {
    if (_recorded) return;
    _recorded = true;
    Telemetry.record("profile_open", fields(closedEarly: closedEarly));
  }

  Map<String, Object?> fields({required bool closedEarly}) => {
        "own_server": ownServer,
        "cached": cached,
        "closed_early": closedEarly,
        "shown_ms": shownMs,
        "fetch_ms": fetchMs,
        "profile_ms": profileMs,
        "presence_ms": presenceMs,
        if (fetchDone) ...Telemetry.errorFields(fetchError),
        "color_source": colorSource,
        "color_ms": colorMs,
        "color_late": colorLate,
        "timezone_init_ms": timezoneInitMs,
        "has_banner": hasBanner,
        "has_avatar": hasAvatar,
        "has_timezone": hasTimezone,
        "banner_ms": bannerMs,
        "banner_full_ms": bannerFullMs,
        if (hasBanner) "banner_failed": bannerFailed,
        "avatar_ms": avatarMs,
        "avatar_full_ms": avatarFullMs,
        if (hasAvatar) "avatar_failed": avatarFailed,
      };
}
