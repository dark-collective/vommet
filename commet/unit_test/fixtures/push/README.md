# Push payload fixtures (Vommet issue 1047)

Real push bodies Synapse and Tuwunel POSTed to a push gateway, anonymized.
`unit_test/push_payload_fixtures_test.dart` runs each through the background
push handler's decisions (tweaks, the on-device push rule check) and checks
the outcome in `expected.json`.

## Where they come from

The push pipeline integration test
(`integration_test/matrix/push_pipeline_test.dart`) registers an
`event_id_only` and a full-format pusher at a fake gateway and writes every
push it gets to `$OUT/push-payloads/<server>/<case>-<format>.json`, plus
`matrix.json` with the outcome the app gave each one. Cases that the default
rules don't push (muted, reaction, redaction) have no files.

They come from the test's gateway, not from "Copy notification debug" dumps:
that dump keeps numbers only (no push bodies), by design. `matrix.json` is
not committed; it lives in the integration run's artifact.

## Adding a quirk seen in the field

Write the fixture by hand from a gateway capture (anonymized as below) and add
its row to `expected.json`. `anonymize.py` rewrites `expected.json` from
`matrix.json`, so re-add hand-written rows after a refresh.

## Refreshing

1. Run the push pipeline integration test on each server (`IT_HS=synapse` or
   Tuwunel) and keep `$OUT/push-payloads/`.
2. `python3 unit_test/fixtures/push/anonymize.py <$OUT/push-payloads> unit_test/fixtures/push`
   (from `commet/`; it rewrites the fixtures and `expected.json`, which is
   derived from each server's `matrix.json`).
3. Run `flutter test unit_test/push_payload_fixtures_test.dart`.

## Anonymization

- Room ids: `!room-dm`, `!room-group` (also mention, keyword, thread),
  `!room-group3`, `!room-e2ee`, all `:example.org`.
- Event ids: `$event-<case>` (the thread's relation points at
  `$event-group`, its root).
- Users: `@alice:example.org` (receiver), `@bob:example.org` (sender),
  `@carol:example.org`.
- `pushkey` becomes `pushkey-<format>`, `local_client_id` `client-alice`,
  `pushkey_ts` 1700000000, `room_name` `Group room` / `Group3 room` / ...
- Everything else (structure, counts, prio, tweaks, content, ciphertext,
  the test message text and keyword) is kept as sent.
