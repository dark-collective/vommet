/// What to tell the user after "Retry Decrypt" (Vommet issue 1061).
enum RetryDecryptOutcome { decrypted, askedOtherDevices, onlyDevice }

/// [ownDevices] is the own user's device list, or null when it is not known
/// (or outdated). [onlyDevice] is returned only when it is certain no other
/// non-blocked device could answer the key request.
RetryDecryptOutcome retryDecryptOutcome(
  bool keyNowPresent,
  Iterable<({String deviceId, bool blocked})>? ownDevices,
  String? ownDeviceId,
) {
  if (keyNowPresent) return RetryDecryptOutcome.decrypted;
  if (ownDevices == null || ownDeviceId == null) {
    return RetryDecryptOutcome.askedOtherDevices;
  }
  final hasOther =
      ownDevices.any((d) => d.deviceId != ownDeviceId && !d.blocked);
  return hasOther
      ? RetryDecryptOutcome.askedOtherDevices
      : RetryDecryptOutcome.onlyDevice;
}
