// Vommet: an empty stand-in, see pubspec.yaml. Registers nothing: Vommet
// never calls flutter_secure_storage on Windows.
class FlutterSecureStorageWindowsStub {
  static void registerWith() {}
}
