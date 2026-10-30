/// Vommet: web stand-in for owner_only_native.dart (no file system).
class OwnerOnly {
  static Future<bool> directory(String path) async => false;

  static Future<bool> file(String path) async => false;

  static Future<bool> isOwnerOnly(String path) async => false;

  static int? currentUid() => null;

  static int? ownerOf(String path) => null;

  static bool get checksOwners => false;
}
