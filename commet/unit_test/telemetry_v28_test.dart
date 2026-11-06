// Vommet telemetry schema v28: the web build's `web_env` event.

import 'dart:convert';
import 'dart:io';

import 'package:commet/telemetry/telemetry_schema.dart';
import 'package:commet/telemetry/web_env_telemetry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final source = File("assets/telemetry/schema.json").readAsStringSync();
  final schema = TelemetrySchema.parse(source);

  const chrome =
      "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36";
  const edge = "$chrome Edg/141.0.0.0";
  const firefox =
      "Mozilla/5.0 (X11; Linux x86_64; rv:144.0) Gecko/20100101 Firefox/144.0";
  const safari =
      "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15";

  test("schema is v28 and still accepts v27", () {
    expect(schema.version, greaterThanOrEqualTo(28));
    expect((jsonDecode(source) as Map)["accepts"], contains(27));
  });

  test("engine family matches Flutter's loader", () {
    expect(WebEnvTelemetry.engineFamily("Google Inc.", chrome), "blink");
    expect(WebEnvTelemetry.engineFamily("", edge), "blink");
    expect(WebEnvTelemetry.engineFamily("", firefox), "gecko");
    expect(
        WebEnvTelemetry.engineFamily("Apple Computer, Inc.", safari), "webkit");
    expect(WebEnvTelemetry.engineFamily("Google Inc.", firefox), "blink");
    expect(WebEnvTelemetry.engineFamily("", "SomethingElse/1.0"), "other");
  });

  test("only the major version is read", () {
    expect(WebEnvTelemetry.engineMajor("blink", chrome), 141);
    expect(WebEnvTelemetry.engineMajor("blink", edge), 141);
    expect(WebEnvTelemetry.engineMajor("gecko", firefox), 144);
    expect(WebEnvTelemetry.engineMajor("webkit", safari), 26);
    expect(WebEnvTelemetry.engineMajor("other", chrome), isNull);
    expect(WebEnvTelemetry.engineMajor("gecko", "no version"), isNull);
  });

  test("fallback reason", () {
    expect(WebEnvTelemetry.fallbackReason(wasm: true, supportsWasmGC: true),
        "none");
    expect(WebEnvTelemetry.fallbackReason(wasm: false, supportsWasmGC: true),
        "allowlist");
    expect(WebEnvTelemetry.fallbackReason(wasm: false, supportsWasmGC: false),
        "no_wasmgc");
  });

  test("not on web: no event", () {
    expect(WebEnvTelemetry.fields(), isNull);
  });

  test("web_env validates; free text and extra fields don't", () {
    final ok = {
      "e": "web_env",
      "t": 1200,
      "build": "js",
      "engine": "gecko",
      "engine_major": 144,
      "cross_origin_isolated": true,
      "webgl": 2,
      "fallback_reason": "allowlist",
    };
    expect(schema.validateEvent(ok), isTrue);
    expect(schema.validateEvent({...ok, "engine": "Firefox"}), isFalse);
    expect(schema.validateEvent({...ok, "webgl": 3}), isFalse);
    expect(schema.validateEvent({...ok, "user_agent": firefox}), isFalse);
    final noMajor = Map.of(ok)..remove("engine_major");
    expect(schema.validateEvent(noMajor), isTrue);
  });
}
