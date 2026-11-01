#ifndef RUNNER_TRAY_ICON_H_
#define RUNNER_TRAY_ICON_H_

#include <flutter/binary_messenger.h>

// Vommet issue 632: the tray icon on Windows (Shell_NotifyIcon), driven from
// lib/utils/tray/windows_tray.dart over the channel "im.nether.vommet/tray".
// Dart calls start, setIcon, setMenuLabel and dispose; the runner calls
// activate (left click), menuClicked(index) and available(bool) back.
void TrayIconRegister(flutter::BinaryMessenger* messenger);

// Removes the icon (the app is exiting).
void TrayIconShutdown();

#endif  // RUNNER_TRAY_ICON_H_
