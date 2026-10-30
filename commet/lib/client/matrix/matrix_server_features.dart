import 'package:commet/client/matrix/components/profile/matrix_profile_component.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/debug/log.dart';
import 'package:matrix/matrix.dart';

/// Vommet: what the account's homeserver lets the profile card change, found
/// once per account per run.
///
/// Presence has no capability, so it's probed: a server with presence off
/// refuses `GET /presence/{self}/status` (Tuwunel: 403 "Presence is disabled
/// on this server"; servers without the endpoint: 404 / M_UNRECOGNIZED).
/// Avatar and banner come from `/capabilities`: Matrix 1.16 `m.profile_fields`
/// (or MSC4133's unstable name), and before that the avatar's
/// `m.set_avatar_url`. Custom fields such as the banner need profile fields.
class MatrixServerFeatures {
  final bool presence;
  final bool avatar;
  final bool banner;

  /// The status message lives in presence when the server has it, otherwise
  /// in Commet's profile field (which Commet already reads).
  final bool profileStatus;

  bool get statusMessage => presence || profileStatus;

  const MatrixServerFeatures({
    required this.presence,
    required this.avatar,
    required this.banner,
    required this.profileStatus,
  });

  static final Map<String, Future<MatrixServerFeatures>> _cache = {};

  static Future<MatrixServerFeatures> of(MatrixClient client) =>
      _cache.putIfAbsent(client.identifier, () => _probe(client));

  static Future<MatrixServerFeatures> _probe(MatrixClient client) async {
    final mx = client.matrixClient;

    var presence = true;
    try {
      await mx.request(RequestType.GET,
          "/client/v3/presence/${Uri.encodeComponent(mx.userID!)}/status");
    } on MatrixException catch (e) {
      presence = !(e.error == MatrixError.M_FORBIDDEN ||
          e.error == MatrixError.M_UNRECOGNIZED ||
          e.response?.statusCode == 403 ||
          e.response?.statusCode == 404);
    } catch (e, s) {
      // Network trouble says nothing about the server; assume the default.
      Log.onError(e, s, content: "Could not probe presence support");
    }

    Map<String, dynamic> capabilities = {};
    try {
      final response =
          await mx.request(RequestType.GET, "/client/v3/capabilities");
      capabilities = Map<String, dynamic>.from(
          (response["capabilities"] as Map?) ?? const {});
    } catch (e, s) {
      Log.onError(e, s, content: "Could not read server capabilities");
    }

    final fields = (capabilities["m.profile_fields"] ??
        capabilities["uk.tcpip.msc4133.profile_fields"]) as Map?;

    bool fieldAllowed(String name) {
      if (fields == null) {
        if (name != "avatar_url") return false;
        final legacy = capabilities["m.set_avatar_url"] as Map?;
        return legacy?["enabled"] != false;
      }
      if (fields["enabled"] != true) return false;
      final allowed = fields["allowed"];
      if (allowed is List && !allowed.contains(name)) return false;
      final disallowed = fields["disallowed"];
      return !(disallowed is List && disallowed.contains(name));
    }

    final features = MatrixServerFeatures(
      presence: presence,
      avatar: fieldAllowed("avatar_url"),
      banner: fieldAllowed(MatrixProfileComponent.bannerKey),
      profileStatus: fieldAllowed(MatrixProfileComponent.statusKey),
    );
    Log.i("Server features for ${client.identifier}: presence=$presence "
        "avatar=${features.avatar} banner=${features.banner} "
        "profileStatus=${features.profileStatus}");
    return features;
  }
}
