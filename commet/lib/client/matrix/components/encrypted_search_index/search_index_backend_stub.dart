// Vommet: the web build has no encrypted search index.
import 'package:commet/client/matrix/components/encrypted_search_index/search_index_backend.dart';

Future<SearchIndexBackend> openSearchIndexBackend(String path,
        {String? ownUserId, required String account}) =>
    throw UnsupportedError("No encrypted search index on this platform");
