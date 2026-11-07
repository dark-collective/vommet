// Vommet issue 1216: local viewing corrections, never transformed media bytes.
import 'dart:convert';

import 'package:commet/client/matrix/matrix_mxc_image_provider.dart';
import 'package:commet/debug/log.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:flutter/painting.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:shared_preferences/shared_preferences.dart';

class ViewerRotations {
  ViewerRotations(this.preferences);

  final SharedPreferences? Function() preferences;
  final _active = <Object, ViewerRotation>{};
  final _pending = <String, (int, Object)>{};
  final _anonymous = Expando<Object>();
  final _accounts = Expando<String>();
  final _signedOut = Expando<bool>();
  Future<void> _writes = Future.value();
  Future<void> get settled => _writes;

  String? _account(matrix.Client client) {
    final user = client.userID;
    final server = client.homeserver;
    if (user == null || server == null) return _accounts[client];
    final uri = server.replace(
      scheme: server.scheme.toLowerCase(),
      host: server.host.toLowerCase(),
    );
    return _accounts[client] = 'vommet_viewer_rotation.v1.'
        '${sha256.convert(utf8.encode(jsonEncode([
          uri.toString().replaceFirst(RegExp(r'/+$'), ''),
          user
        ])))}.';
  }

  /// Called while the session still has its account identity, including restore.
  void rememberAccount(matrix.Client client) {
    _signedOut[client] = false;
    _account(client);
  }

  ViewerRotation acquire(ImageProvider image) {
    String? prefix;
    String? key;
    bool enabled = true;
    if (image is MatrixMxcImage) {
      final client = image.client;
      enabled = _signedOut[client] != true && client.isLogged();
      if (enabled && image.identifier.isScheme('mxc')) {
        prefix = _account(client);
        if (prefix != null) {
          key =
              '$prefix${sha256.convert(utf8.encode(image.identifier.toString()))}';
        }
      }
    }
    final identity = key ?? (_anonymous[image] ??= Object());
    final rotation = _active.putIfAbsent(identity, () {
      final stored =
          key == null ? null : _pending[key]?.$1 ?? preferences()?.get(key);
      final turns = stored is int && stored > 0 && stored < 4 ? stored : 0;
      if (key != null && stored != null && turns == 0) {
        final invalidKey = key;
        _queue(() async {
          await preferences()?.remove(invalidKey);
        });
      }
      return ViewerRotation._(
        this,
        identity,
        prefix,
        key,
        turns,
        enabled,
      );
    });
    rotation._references++;
    return rotation;
  }

  void _queue(Future<void> Function() write) {
    _writes = _writes.then((_) => write()).catchError((Object error) {
      Log.w('Could not save viewer rotation: $error');
    });
  }

  /// Both local and remote sign-out invalidate live leases before queued writes.
  Future<void> forgetAccount(matrix.Client client) {
    _signedOut[client] = true;
    final prefix = _accounts[client] ?? _account(client);
    if (prefix == null) return Future.value();
    _pending.removeWhere((key, _) => key.startsWith(prefix));
    for (final rotation in _active.values.toList()) {
      if (rotation._prefix == prefix) {
        rotation._enabled = false;
        _active.remove(rotation._identity);
        rotation.value = 0;
      }
    }
    _queue(() async {
      final prefs = preferences();
      if (prefs == null) return;
      for (final key in prefs.getKeys().where(
            (key) => key.startsWith(prefix),
          )) {
        await prefs.remove(key);
      }
    });
    return settled;
  }
}

/// A reference-counted lease shared by the image and its menu, not decode caches.
class ViewerRotation extends ValueNotifier<int> {
  ViewerRotation._(
    this._store,
    this._identity,
    this._prefix,
    this._key,
    super.value,
    this._enabled,
  );

  final ViewerRotations _store;
  final Object _identity;
  final String? _prefix;
  final String? _key;
  bool _enabled;
  int _references = 0;

  void turn(int direction) => setTurns((value + direction) % 4);

  void setTurns(int turns) {
    if (!_enabled || turns == value) return;
    value = turns;
    final key = _key;
    if (key == null) return;
    // Vommet issue 1216: repeated angles can belong to different queued writes.
    final pending = (turns, Object());
    _store._pending[key] = pending;
    _store._queue(() async {
      if (!_enabled) return;
      final prefs = _store.preferences();
      if (turns == 0) {
        await prefs?.remove(key);
      } else {
        await prefs?.setInt(key, turns);
      }
      if (_store._pending[key] == pending) _store._pending.remove(key);
    });
  }

  void release() {
    if (--_references != 0) return;
    if (identical(_store._active[_identity], this)) {
      _store._active.remove(_identity);
    }
    dispose();
  }
}
