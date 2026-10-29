// Vommet telemetry schema v35: how long an opened profile card took, numbers,
// booleans and fixed words only.

import 'dart:async';
import 'dart:io';

import 'package:commet/telemetry/profile_open_telemetry.dart';
import 'package:commet/telemetry/telemetry_schema.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final schema = TelemetrySchema.parse(
    File("assets/telemetry/schema.json").readAsStringSync(),
  );

  Map<String, Object?> event(Map<String, Object?> fields) => {
        "e": "profile_open",
        "t": 900000,
        for (final MapEntry(:key, :value) in fields.entries)
          if (value != null) key: value,
      };

  test("a card shown from the cache, refreshed from another server", () {
    var now = 0;
    final r = ProfileOpenRecord(ownServer: false, clock: () => now);
    r
      ..cached = true
      ..hasBanner = true
      ..hasAvatar = true;
    now = 40;
    r.shownMs = r.now();
    r
      ..colorSource = "banner"
      ..colorMs = 900
      ..colorLate = true
      ..colorDone = true
      ..avatarMs = 120
      ..avatarFullMs = 1500
      ..bannerMs = 900;
    r
      ..fetchMs = 3400
      ..profileMs = 3100
      ..presenceMs = 300
      ..fetchDone = true;

    // The full banner is still on its way.
    expect(r.settled, isFalse);
    r.bannerFullMs = 4200;
    expect(r.settled, isTrue);

    final fields = r.fields(closedEarly: false);
    expect(fields["shown_ms"], 40);
    expect(fields["cached"], isTrue);
    expect(fields["outcome"], "ok");
    expect(schema.validateEvent(event(fields)), isTrue);
  });

  test("a failed lookup carries its error kind, never its message", () {
    final r = ProfileOpenRecord(ownServer: true, clock: () => 10000)
      ..fetchMs = 10000
      ..fetchError = TimeoutException("profile of @someone:example.org")
      ..fetchDone = true
      ..colorSource = "default"
      ..colorDone = true
      ..shownMs = 10000;
    final fields = r.fields(closedEarly: false);
    expect(fields["outcome"], "error");
    expect(fields["error_kind"], "timeout");
    expect(fields.values.whereType<String>().join(" "),
        isNot(contains("someone")));
    expect(schema.validateEvent(event(fields)), isTrue);
  });

  test("closing before anything arrived still makes a valid event", () {
    final r = ProfileOpenRecord(ownServer: false, clock: () => 0);
    expect(r.settled, isFalse);
    final fields = r.fields(closedEarly: !r.settled);
    expect(fields["closed_early"], isTrue);
    expect(fields.containsKey("outcome"), isFalse);
    expect(schema.validateEvent(event(fields)), isTrue);
  });

  test("a picture that failed counts as settled", () {
    final r = ProfileOpenRecord(ownServer: true, clock: () => 0)
      ..shownMs = 5
      ..fetchDone = true
      ..colorDone = true
      ..hasBanner = true
      ..bannerFailed = true;
    expect(r.settled, isTrue);
    expect(schema.validateEvent(event(r.fields(closedEarly: false))), isTrue);
  });

  test("the schema refuses names, ids and unknown color sources", () {
    final base = ProfileOpenRecord(ownServer: false, clock: () => 0)
      ..shownMs = 1
      ..colorSource = "memory"
      ..colorDone = true;
    final fields = base.fields(closedEarly: true);
    expect(schema.validateEvent(event(fields)), isTrue);
    for (final (key, value) in [
      ("color_source", "gravatar"),
      ("user_id", "@a:b"),
      ("server", "matrix.org"),
      ("display_name", "penguin"),
      ("shown_ms", -1),
    ]) {
      expect(schema.validateEvent(event({...fields, key: value})), isFalse,
          reason: key);
    }
  });
}
