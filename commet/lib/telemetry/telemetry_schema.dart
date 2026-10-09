// Client-side copy of the collector's validator (vommet-proxy
// telemetry/telemetry.js). The schema file assets/telemetry/schema.json is the
// complete list of what may be sent: numbers, booleans, values from fixed
// lists and code identifiers. Anything else is dropped before it leaves the
// device; the collector checks again on its side.

import 'dart:convert';

class TelemetrySchema {
  final Map<String, dynamic> _raw;
  final Map<String, RegExp> _regex = {};

  TelemetrySchema(this._raw);

  factory TelemetrySchema.parse(String json) =>
      TelemetrySchema(jsonDecode(json) as Map<String, dynamic>);

  int get version => _raw["version"] as int;
  int get maxEvents => (_raw["limits"] as Map)["max_events"] as int;
  int get maxBodyBytes => (_raw["limits"] as Map)["max_body_bytes"] as int;

  Map<String, dynamic> get _types => _raw["types"] as Map<String, dynamic>;
  Map<String, dynamic> get _events => _raw["events"] as Map<String, dynamic>;
  Map<String, dynamic> get _envelope =>
      _raw["envelope"] as Map<String, dynamic>;

  RegExp _re(String p) => _regex.putIfAbsent(p, () => RegExp(p));

  Map<String, dynamic> _resolve(Map<String, dynamic> spec) {
    var s = spec;
    for (var i = 0; i < 8 && _types.containsKey(s["type"]); i++) {
      s = {
        ...(_types[s["type"]] as Map<String, dynamic>),
        "required": spec["required"]
      };
    }
    return s;
  }

  bool _check(Map<String, dynamic> spec, Object? value) {
    final s = _resolve(spec);
    switch (s["type"]) {
      case "int":
        return value is int &&
            value >= (s["min"] as num) &&
            value <= (s["max"] as num);
      case "bool":
        return value is bool;
      case "enum":
        return value is String && (s["values"] as List).contains(value);
      case "pattern":
        return value is String && _re(s["pattern"] as String).hasMatch(value);
      case "list":
        return value is List &&
            value.length <= (s["max"] as int) &&
            value.every((v) => _check(s["item"] as Map<String, dynamic>, v));
      case "object":
        return _checkFields(s["fields"] as Map<String, dynamic>, value);
      default:
        return false;
    }
  }

  bool _checkFields(Map<String, dynamic> fields, Object? obj,
      {List<String> reserved = const []}) {
    if (obj is! Map<String, dynamic>) return false;
    for (final k in obj.keys) {
      if (reserved.contains(k)) continue;
      final spec = fields[k];
      if (spec == null) return false;
      if (!_check(spec as Map<String, dynamic>, obj[k])) return false;
    }
    for (final e in fields.entries) {
      if ((e.value as Map)["required"] == true && !obj.containsKey(e.key)) {
        return false;
      }
    }
    return true;
  }

  bool hasEvent(String name) => _events.containsKey(name);

  /// Event shape: {"e": name, "t": ms since session start, ...fields}.
  bool validateEvent(Map<String, dynamic> ev) {
    final name = ev["e"];
    if (name is! String || !_events.containsKey(name)) return false;
    if (!_check({"type": "ms", "required": true}, ev["t"])) return false;
    return _checkFields(_events[name] as Map<String, dynamic>, ev,
        reserved: const ["e", "t"]);
  }

  bool validateEnvelope(Map<String, dynamic> env) {
    final fields = Map<String, dynamic>.from(_envelope)..remove("events");
    return _checkFields(fields, env);
  }

  /// True when [value] is an allowed value of the named enum type
  /// (e.g. "error_kind"), so callers can fall back to "unknown".
  bool enumAllows(String type, String value) {
    final t = _types[type] as Map<String, dynamic>?;
    return t != null &&
        t["type"] == "enum" &&
        (t["values"] as List).contains(value);
  }

  bool matchesType(String type, Object? value) => _check({"type": type}, value);
}
