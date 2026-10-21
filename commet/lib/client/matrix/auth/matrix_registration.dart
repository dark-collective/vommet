import 'package:commet/client/auth.dart';
import 'package:commet/client/client.dart';
import 'package:commet/client/matrix/auth/matrix_oidc_login_flow.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/config/build_config.dart';
import 'package:commet/debug/log.dart';
import 'package:matrix/matrix.dart' as matrix;

// Vommet: creating a Matrix account from inside the app (Vommet issue 254).
//
// Servers with next-gen auth (MAS, MSC2964) create accounts on their own
// web page, which we open with `prompt=create`. Older servers take a
// `/register` request with user-interactive auth, which we drive here for
// the stages we can show in the app.

/// How a homeserver lets people create an account.
sealed class RegistrationMethod {}

/// Sign-up happens on the server's own page in the browser.
class RegistrationInBrowser extends RegistrationMethod {}

/// Sign-up through `/register`, in the app.
class RegistrationInApp extends RegistrationMethod {
  /// The flow we will follow: the first one whose stages we all support.
  final List<String> stages;
  final Map<String, Object?> params;

  RegistrationInApp(this.stages, this.params);

  bool get needsToken => stages.contains(registrationTokenStage);
  bool get needsTerms => stages.contains(termsStage);
}

/// The server takes sign-ups, but only through steps the app can't do.
class RegistrationUnsupported extends RegistrationMethod {
  final List<String> missingStages;
  RegistrationUnsupported(this.missingStages);
}

/// The server doesn't take sign-ups from apps at all (invite-only servers,
/// or sign-ups run somewhere else).
class RegistrationClosed extends RegistrationMethod {}

const registrationTokenStage = "m.login.registration_token";
const termsStage = "m.login.terms";
const recaptchaStage = "m.login.recaptcha";
const dummyStage = "m.login.dummy";

/// Stages the app can complete. reCAPTCHA goes through the spec's web
/// fallback page.
const supportedRegistrationStages = {
  registrationTokenStage,
  termsStage,
  recaptchaStage,
  dummyStage,
};

/// Picks the flow to follow: the shortest one made only of stages we
/// support, or null when every flow needs something we can't do.
List<String>? chooseRegistrationFlow(List<List<String>> flows) {
  final usable = flows
      .where((f) => f.every(supportedRegistrationStages.contains))
      .toList()
    ..sort((a, b) => a.length.compareTo(b.length));
  return usable.firstOrNull;
}

/// Asks [mx]'s homeserver how it takes sign-ups. [mx] must already have its
/// homeserver set.
Future<RegistrationMethod> detectRegistrationMethod(matrix.Client mx) async {
  if (MatrixOidcLoginFlow.isSupportedPlatform) {
    try {
      final metadata = await mx.getAuthMetadata();
      if (MatrixOidcLoginFlow.isUsable(metadata)) {
        // A next-gen auth server ignores /register; it either offers
        // "create" on its own page or takes no sign-ups from apps.
        return metadata.promptValuesSupported?.contains("create") == true
            ? RegistrationInBrowser()
            : RegistrationClosed();
      }
    } catch (error) {
      Log.i("No OAuth 2.0 metadata for sign-up: $error");
    }
  }

  try {
    // An empty request only asks for the flows; no account is made.
    await mx.request(matrix.RequestType.POST, "/client/v3/register",
        data: <String, Object?>{});
    return RegistrationClosed();
  } on matrix.MatrixException catch (e) {
    if (!e.requireAdditionalAuthentication) return RegistrationClosed();

    final flows =
        (e.authenticationFlows ?? []).map((f) => f.stages.toList()).toList();
    final chosen = chooseRegistrationFlow(flows);
    if (chosen != null) {
      return RegistrationInApp(chosen, e.authenticationParams ?? {});
    }

    final missing = flows
        .expand((f) => f)
        .where((s) => !supportedRegistrationStages.contains(s))
        .toSet()
        .toList();
    return RegistrationUnsupported(missing);
  }
}

/// The spec's fallback page for a stage the app can't draw itself.
Uri registrationFallbackUrl(Uri homeserver, String stage, String session) {
  return homeserver.replace(
      path: "/_matrix/client/v3/auth/$stage/fallback/web",
      queryParameters: {"session": session});
}

/// Creates the account through `/register` and signs in to it.
class MatrixRegistrationFlow implements LoginFlow {
  final RegistrationInApp method;
  final String username;
  final String password;
  final String? token;

  /// Opens the web fallback for [stage] and resolves once the user says
  /// they've finished there; false cancels sign-up.
  final Future<bool> Function(String stage, Uri fallbackUrl) completeInBrowser;

  MatrixRegistrationFlow({
    required this.method,
    required this.username,
    required this.password,
    required this.completeInBrowser,
    this.token,
  });

  @override
  Future<LoginResult> submit(Client client) async {
    if (client is! MatrixClient) return LoginResultFailed();
    final mx = client.getMatrixClient();

    String? session;
    var completed = <String>{};
    matrix.AuthenticationData? auth;

    // Each pass sends one stage. The server answers 401 with what's done
    // until the last stage, then registers and signs in.
    for (var attempt = 0; attempt <= method.stages.length + 1; attempt++) {
      try {
        await mx.register(
          username: username,
          password: password,
          initialDeviceDisplayName: BuildConfig.appName,
          auth: auth,
        );
        return mx.isLogged() ? LoginResultSuccess() : LoginResultFailed();
      } on matrix.MatrixException catch (e) {
        if (!e.requireAdditionalAuthentication) {
          return LoginResultError(e.errorMessage);
        }
        if (auth != null && e.raw["errcode"] != null) {
          // The stage we just sent was refused (e.g. a wrong token).
          return LoginResultError(e.errorMessage);
        }

        session = e.session ?? session;
        completed = e.completedAuthenticationFlows.toSet();
        final next =
            method.stages.where((s) => !completed.contains(s)).firstOrNull;
        if (next == null || session == null) return LoginResultFailed();

        final stageAuth = await _authFor(mx, next, session);
        if (stageAuth == null) return LoginResultCancelled();
        auth = stageAuth;
      }
    }

    return LoginResultFailed();
  }

  Future<matrix.AuthenticationData?> _authFor(
      matrix.Client mx, String stage, String session) async {
    switch (stage) {
      case registrationTokenStage:
        return _StageAuth(stage, session, {"token": token ?? ""});
      case termsStage:
      case dummyStage:
        // Terms were accepted on the form before sign-up started.
        return _StageAuth(stage, session, const {});
      default:
        final url = registrationFallbackUrl(mx.homeserver!, stage, session);
        if (!await completeInBrowser(stage, url)) return null;
        return matrix.AuthenticationData(session: session);
    }
  }
}

class _StageAuth extends matrix.AuthenticationData {
  final Map<String, Object?> extra;

  _StageAuth(String type, String session, this.extra)
      : super(type: type, session: session);

  @override
  Map<String, Object?> toJson() => {...super.toJson(), ...extra};
}

/// The terms a server asks new users to accept (`m.login.terms` params),
/// as (name, url) pairs in the user's language when offered.
List<(String, Uri)> registrationPolicies(Map<String, Object?> params,
    {String language = "en"}) {
  final terms = params[termsStage];
  if (terms is! Map) return [];
  final policies = terms["policies"];
  if (policies is! Map) return [];

  final result = <(String, Uri)>[];
  for (final policy in policies.values) {
    if (policy is! Map) continue;
    final localized = policy[language] ??
        policy.values
            .whereType<Map>()
            .where((v) => v["url"] != null)
            .firstOrNull;
    if (localized is! Map) continue;
    final url = Uri.tryParse(localized["url"]?.toString() ?? "");
    if (url == null) continue;
    result.add((localized["name"]?.toString() ?? url.host, url));
  }
  return result;
}
