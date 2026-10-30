import 'package:commet/cache/drift_file_cache.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

// Vommet: an image that is still loading when the file cache closes (sign-out,
// test teardown) used to throw an uncaught ConnectionClosedException from
// DriftFileCache.hasFile. A closed cache now answers like an empty one.
void main() {
  test("a closed file cache reports a miss instead of throwing", () async {
    var cache = DriftFileCache();
    cache.database = DriftFileCacheDatabase(NativeDatabase.memory());
    var db = cache.database!;
    await db.into(db.fileCacheEntry).insert(FileCacheEntryCompanion.insert(
        id: "mxc://example.org/abc",
        path: "/nonexistent/abc",
        lastAccessedTimestamp: 0));

    await cache.close();

    expect(await cache.hasFile("mxc://example.org/abc"), isFalse);
    expect(await cache.getFile("mxc://example.org/abc"), isNull);
  });
}
