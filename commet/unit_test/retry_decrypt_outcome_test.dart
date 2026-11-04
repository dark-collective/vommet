import 'package:commet/client/matrix/retry_decrypt_outcome.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const me = (deviceId: "ME", blocked: false);

  test("key present", () {
    expect(
        retryDecryptOutcome(true, [me], "ME"), RetryDecryptOutcome.decrypted);
  });

  test("device list unknown", () {
    expect(retryDecryptOutcome(false, null, "ME"),
        RetryDecryptOutcome.askedOtherDevices);
  });

  test("only this device", () {
    expect(
        retryDecryptOutcome(false, [me], "ME"), RetryDecryptOutcome.onlyDevice);
  });

  test("this device and a blocked one", () {
    expect(
        retryDecryptOutcome(
            false, [me, (deviceId: "OLD", blocked: true)], "ME"),
        RetryDecryptOutcome.onlyDevice);
  });

  test("this device and another active one", () {
    expect(
        retryDecryptOutcome(
            false, [me, (deviceId: "PHONE", blocked: false)], "ME"),
        RetryDecryptOutcome.askedOtherDevices);
  });

  test("own device id unknown", () {
    expect(retryDecryptOutcome(false, [me], null),
        RetryDecryptOutcome.askedOtherDevices);
  });
}
