import 'dart:io';

import 'package:commet/config/platform_utils.dart';
import 'package:win32_registry/win32_registry.dart';

Future<void> registerUriHandlers() async {
  if (PlatformUtils.isWindows) {
    await register("commetchat");
    // Vommet (#85): matrix: URIs, unless another app already handles them.
    if (_unclaimedOrOurs("matrix")) await register("matrix");
  }
}

bool _unclaimedOrOurs(String scheme) {
  try {
    final key = Registry.openPath(RegistryHive.currentUser,
        path: 'Software\\Classes\\$scheme\\shell\\open\\command');
    final command = key.getStringValue('');
    key.close();
    return command == null || command.contains(Platform.resolvedExecutable);
  } catch (_) {
    // No handler registered yet.
    return true;
  }
}

Future<void> register(String scheme) async {
  String appPath = Platform.resolvedExecutable;

  String protocolRegKey = 'Software\\Classes\\$scheme';
  RegistryValue protocolRegValue = const RegistryValue.string(
    'URL Protocol',
    '',
  );
  String protocolCmdRegKey = 'shell\\open\\command';
  RegistryValue protocolCmdRegValue = RegistryValue.string(
    '',
    '"$appPath" "%1"',
  );

  final regKey = Registry.currentUser.createKey(protocolRegKey);
  regKey.createValue(protocolRegValue);
  regKey.createKey(protocolCmdRegKey).createValue(protocolCmdRegValue);
}
