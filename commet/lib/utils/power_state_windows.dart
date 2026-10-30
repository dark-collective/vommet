// Vommet Deep Search (issue 845): Windows battery state through
// GetSystemPowerStatus. Kept apart so web builds never import dart:ffi.
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// The raw SYSTEM_POWER_STATUS fields, or null when the call fails.
({int ac, int flag, int percent, int saver})? readWindowsPowerStatus() {
  final status = calloc<SYSTEM_POWER_STATUS>();
  try {
    if (GetSystemPowerStatus(status) == 0) return null;
    final s = status.ref;
    return (
      ac: s.ACLineStatus,
      flag: s.BatteryFlag,
      percent: s.BatteryLifePercent,
      saver: s.SystemStatusFlag,
    );
  } finally {
    calloc.free(status);
  }
}
