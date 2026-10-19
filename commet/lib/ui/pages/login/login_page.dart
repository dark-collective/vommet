import 'dart:async';

import 'package:commet/client/auth.dart';
import 'package:commet/client/client.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/pages/login/login_page_view.dart';
import 'package:commet/utils/debounce.dart';
import 'package:commet/utils/homeserver_uri.dart';
import 'package:commet/utils/rng.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, this.onSuccess, this.canNavigateBack = false});
  final bool canNavigateBack;
  final Function(Client loggedInClient)? onSuccess;

  @override
  State<LoginPage> createState() => LoginPageState();
}

class LoginPageState extends State<LoginPage> {
  String get messageLoginFailed => Intl.message(
        "Login Failed...",
        name: "messageLoginFailed",
        desc: "Generic text to show that an attempted login has failed",
      );

  String get messageAlreadyLoggedIn => Intl.message(
        "You have already logged in to this account",
        name: "messageAlreadyLoggedIn",
        desc:
            "An error message displayed when the user attempts to add an account which has already been logged in to on this device",
      );

  String get messageInvalidUsernameOrPassword => Intl.message(
      "Invalid username or password",
      name: "messageInvalidUsernameOrPassword",
      desc:
          "An error message displayed when the user attempts to log into an account using the wrong username/password combination");

  String messageHomeserverNotFound(String server) => Intl.message(
      "Couldn't find a Matrix server at $server",
      args: [server],
      name: "messageHomeserverNotFound",
      desc:
          "An error message shown under the homeserver field when no Matrix server answers at the address the user typed");

  StreamSubscription? progressSubscription;
  double? progress;
  List<LoginFlow>? loginFlows;
  Client? loginClient;

  // Vommet: completes once loginClient is set. Opening its database can take
  // longer than the homeserver debounce (IndexedDB on web), and the first
  // lookup then returned early, leaving the spinner up for good.
  final Completer<void> _loginClientReady = Completer<void>();

  final Debouncer homeserverUpdateDebouncer = Debouncer(
    delay: const Duration(seconds: 1),
  );

  bool loadingServerInfo = false;
  bool isServerValid = false;
  bool isLoggingIn = false;

  // Vommet (Vommet issue 38): shown under the homeserver field when no Matrix
  // server answered, and under the password field when the server rejected
  // the username or password.
  String? homeserverError;
  String? credentialsError;

  // Vommet: a slow lookup for an address the user has since changed must
  // not overwrite the newer one's result.
  int homeserverLookup = 0;

  @override
  void initState() {
    var internalId = RandomUtils.getRandomString(20);
    MatrixClient.create(internalId).then((client) {
      loginClient = client;
      if (!_loginClientReady.isCompleted) _loginClientReady.complete();

      progressSubscription = loginClient!.connectionStatusChanged.stream.listen(
        onLoginProgressChanged,
      );
    });

    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return LoginPageView(
      canNavigateBack: widget.canNavigateBack,
      progress: progress,
      updateHomeserver: (value) {
        // Vommet: keep the current flows until the lookup answers. Clearing
        // them hid the username field while the user was typing a full
        // Matrix ID into it. isServerValid = false blocks login meanwhile.
        setState(() {
          isServerValid = false;
          loadingServerInfo = true;
          homeserverError = null;
          credentialsError = null;
        });
        homeserverUpdateDebouncer.run(() => updateHomeserver(value));
      },
      flows: loginFlows,
      doSsoLogin: doSsoLogin,
      doOidcLogin: doOidcLogin,
      doPasswordLogin: doPasswordLogin,
      isLoggingIn: isLoggingIn,
      loadingServerInfo: loadingServerInfo,
      hasSsoSupport: loginFlows?.whereType<SsoLoginFlow>().isNotEmpty == true,
      hasOidcSupport: loginFlows?.whereType<OidcLoginFlow>().isNotEmpty == true,
      hasPasswordSupport:
          loginFlows?.whereType<PasswordLoginFlow>().isNotEmpty == true,
      isServerValid: isServerValid,
      homeserverError: homeserverError,
      credentialsError: credentialsError,
    );
  }

  Future<void> doLogin(Future<LoginResult> Function() login,
      {bool saveCredentials = false}) async {
    if (loginClient == null) return;
    if (isServerValid == false) {
      return;
    }

    setState(() {
      isLoggingIn = true;
      credentialsError = null;
    });

    LoginResult result;

    try {
      result = await login();
    } catch (error, trace) {
      Log.onError(error, trace);
      result = LoginResultError(error.toString());
    }

    if (!(result is LoginResultSuccess) && mounted) {
      setState(() {
        isLoggingIn = false;
        // Said under the password field rather than in a dialog.
        if (result is LoginResultInvalidCredentials) {
          credentialsError = messageInvalidUsernameOrPassword;
        }
      });
    }

    String? message = switch (result) {
      LoginResultSuccess _ => null,
      LoginResultError e => e.errorMessage,
      LoginResultCancelled _ => "Login Canceled",
      LoginResultAlreadyLoggedIn _ => messageAlreadyLoggedIn,
      LoginResultFailed _ => messageLoginFailed,
      LoginResultInvalidCredentials _ => null,
      LoginResult() => messageLoginFailed,
    };

    if (message != null) {
      if (mounted) {
        AdaptiveDialog.show(
          context,
          title: "Login failed",
          builder: (_) => tiamat.Text(
            message,
          ),
        );
      }
    }

    if (result is LoginResultSuccess) {
      // Vommet (Vommet issue 305): let the password manager save what was
      // typed, before onSuccess closes the page and the form's autofill
      // group discards it.
      if (saveCredentials) TextInput.finishAutofillContext();
      clientManager?.addClient(loginClient!);
      widget.onSuccess?.call(loginClient!);
    }
  }

  Future<void> doSsoLogin(SsoLoginFlow flow) async {
    if (loginClient == null) return;
    await doLogin(() => loginClient!.executeLoginFlow(flow));
  }

  Future<void> doOidcLogin(OidcLoginFlow flow) async {
    if (loginClient == null) return;
    await doLogin(() => loginClient!.executeLoginFlow(flow));
  }

  Future<void> doPasswordLogin(
    PasswordLoginFlow flow,
    String username,
    String password,
  ) async {
    if (loginClient == null) return;
    flow.username = username;
    flow.password = password;

    await doLogin(() => loginClient!.executeLoginFlow(flow),
        saveCredentials: true);
  }

  void onLoginProgressChanged(ClientConnectionStatusUpdate event) {
    if (!mounted) return;
    setState(() {
      progress = event.progress;
    });
  }

  Future<void> updateHomeserver(String input) async {
    // Vommet: runs from a debounce timer and awaits the server; the page
    // may be gone by then.
    if (!mounted) return;
    if (loginClient == null) await _loginClientReady.future;
    if (loginClient == null || !mounted) return;

    setState(() {
      loadingServerInfo = true;
      isServerValid = false;
    });

    var lookup = ++homeserverLookup;
    var uri = homeserverUriFromInput(input);
    var result =
        uri == null ? (false, null) : await loginClient!.setHomeserver(uri);
    if (!mounted) return;

    if (lookup != homeserverLookup) return;
    setState(() {
      loadingServerInfo = false;
      isServerValid = result.$1;
      loginFlows = result.$2;
      homeserverError = isServerValid || input.isEmpty
          ? null
          : messageHomeserverNotFound(input);
    });
  }
}
