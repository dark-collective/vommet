// Vommet (schema v17): how long sending a message takes and whether it
// worked, as a `message_send` event per text message, reply, edit, thread
// message, reaction, redaction and sticker. Records the message's length in
// characters, whether it had formatting and how many people it mentioned,
// the time spent rendering markdown and the time the SDK took to send
// (including its own retries). Never the text, who was mentioned or which
// room. A message the SDK gave up on without an exception (it marks the
// event failed and returns null) is recorded as an error without a type.

import 'package:commet/telemetry/telemetry.dart';

class MessageSendTelemetry {
  static void record({
    required String kind,
    required bool encrypted,
    required int sendMs,
    int? chars,
    bool? html,
    int? mentions,
    int? markdownMs,
    Object? error,
    bool failed = false,
  }) {
    if (!Telemetry.enabled) return;
    Telemetry.record("message_send", {
      "kind": kind,
      "encrypted": encrypted,
      "chars": chars?.clamp(0, 1000000),
      "html": html,
      "mentions": mentions?.clamp(0, 1000000),
      "markdown_ms": markdownMs?.clamp(0, 86400000),
      "send_ms": sendMs.clamp(0, 86400000),
      if (error == null && failed) ...{
        "outcome": "error",
        "error_kind": "unknown"
      } else
        ...Telemetry.errorFields(error),
    });
  }
}
