# Nightly-only integration tests

`nightly-only` (one line, a regular expression matched from the start of a test
name) lists the tests of `integration_test/vommet_runner.dart` that the
candidate runs leave out (vommet-integration.yml) and the nightly "sync-gap"
target runs every night (vommet-nightly.yml). Both workflows read this file,
so it is the only list. A name prefix matches every test it starts: "failed
echo" is both failed-echo tests (with and without "Send while offline").

Operator 11-05: heavy variants belong nightly; candidates keep "sliding sync
gap: own" and "sliding sync gap: encrypted below newer".
