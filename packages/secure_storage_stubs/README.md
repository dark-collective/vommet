# flutter_secure_storage stand-ins

`commet/pubspec.yaml` overrides `flutter_secure_storage_linux` and
`flutter_secure_storage_windows` with these empty packages. Vommet uses
flutter_secure_storage only on Android, iOS and macOS (its local data key);
on Linux and Windows it has its own key stores in
`commet/lib/security/key_vault/`, so the real implementations (libsecret and
jsoncpp at build time on Linux, win32 6 on Windows) are left out.
