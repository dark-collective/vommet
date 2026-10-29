import 'dart:async';

import 'package:commet/client/auth.dart';
import 'package:commet/client/client.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/pages/login/login_page_view.dart';
// Vommet: kept apart from the sorted imports, which other topics edit.
import 'package:commet/ui/pages/create_account/create_account_page.dart';
import 'package:commet/utils/debounce.dart';
import 'package:commet/utils/rng.dart';
import 'package:flutter/material.dart';
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

  StreamSubscription? progressSubscription;
  double? progress;
  List<LoginFlow>? loginFlows;
  Client? loginClient;

  final Debouncer homeserverUpdateDebouncer = Debouncer(
    delay: const Duration(seconds: 1),
  );

  bool loadingServerInfo = false;
  bool isServerValid = false;
  bool isLoggingIn = false;

  @override
  void initState() {
    var internalId = RandomUtils.getRandomString(20);
    MatrixClient.create(internalId).then((client) {
      loginClient = client;

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
        setState(() {
          loginFlows = null;
          isServerValid = false;
          loadingServerInfo = true;
        });
        homeserverUpdateDebouncer.run(() => updateHomeserver(value));
      },
      flows: loginFlows,
      doSsoLogin: doSsoLogin,
      doOidcLogin: doOidcLogin,
      doPasswordLogin: doPasswordLogin,
      onCreateAccount: openCreateAccount,
      isLoggingIn: isLoggingIn,
      loadingServerInfo: loadingServerInfo,
      hasSsoSupport: loginFlows?.whereType<SsoLoginFlow>().isNotEmpty == true,
      hasOidcSupport: loginFlows?.whereType<OidcLoginFlow>().isNotEmpty == true,
      hasPasswordSupport:
          loginFlows?.whereType<PasswordLoginFlow>().isNotEmpty == true,
      isServerValid: isServerValid,
    );
  }

  Future<void> doLogin(Future<LoginResult> Function() login) async {
    if (loginClient == null) return;
    if (isServerValid == false) {
      return;
    }

    setState(() {
      isLoggingIn = true;
    });

    LoginResult? result;

    try {
      result = await login();
    } catch (_) {}

    if (!(result is LoginResultSuccess)) {
      setState(() {
        isLoggingIn = false;
      });
    }

    String? message = switch (result) {
      LoginResultSuccess _ => null,
      LoginResultError e => e.errorMessage,
      LoginResultCancelled _ => "Login Cancelled",
      LoginResultAlreadyLoggedIn _ => messageAlreadyLoggedIn,
      LoginResultFailed _ => messageLoginFailed,
      LoginResult() => throw UnimplementedError(),
      null => throw UnimplementedError(),
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
      clientManager?.addClient(loginClient!);
      widget.onSuccess?.call(loginClient!);
    }
  }

  // Vommet (Vommet issue 254): a new account arrives signed in, and goes
  // through the same steps as a sign-in from here on.
  Future<String?> openCreateAccount() async {
    var result = await Navigator.of(context).push<CreateAccountResult>(
        MaterialPageRoute(builder: (_) => const CreateAccountPage()));

    switch (result) {
      case CreateAccountSignedUp signedUp:
        clientManager?.addClient(signedUp.client);
        widget.onSuccess?.call(signedUp.client);
        return null;
      case CreateAccountSignIn signIn:
        return signIn.server;
      case null:
        return null;
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

    await doLogin(() => loginClient!.executeLoginFlow(flow));
  }

  void onLoginProgressChanged(ClientConnectionStatusUpdate event) {
    if (!mounted) return;
    setState(() {
      progress = event.progress;
    });
  }

  Future<void> updateHomeserver(String input) async {
    if (loginClient == null) return;

    setState(() {
      loginFlows = null;
      loadingServerInfo = true;
      isServerValid = false;
    });

    var uri = Uri.https(input);
    var result = await loginClient!.setHomeserver(uri);

    setState(() {
      loadingServerInfo = false;
      isServerValid = result.$1;
      loginFlows = result.$2;
    });
  }
}
