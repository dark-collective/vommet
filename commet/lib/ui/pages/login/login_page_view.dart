import 'dart:ui';

import 'package:commet/client/auth.dart';
import 'package:commet/config/global_config.dart';
import 'package:commet/ui/atoms/shader/star_trails.dart';
import 'package:commet/ui/navigation/navigation_utils.dart';
import 'package:commet/ui/pages/settings/app_settings_page.dart';
import 'package:commet/ui/pages/settings/categories/about/settings_category_about.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/svg.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/atoms/circle_button.dart';
import 'package:tiamat/tiamat.dart' as tiamat;
// Vommet: kept apart from the sorted imports above, which other topics edit.
import 'package:commet/utils/homeserver_uri.dart';

class LoginPageView extends StatefulWidget {
  const LoginPageView(
      {super.key,
      this.canNavigateBack = false,
      this.progress,
      this.flows,
      required this.isLoggingIn,
      this.homeserverChecked,
      this.doSsoLogin,
      this.doOidcLogin,
      this.doPasswordLogin,
      this.onCreateAccount,
      this.loadingServerInfo = false,
      this.isServerValid = false,
      this.hasSsoSupport = false,
      this.hasOidcSupport = false,
      this.hasPasswordSupport = false,
      this.updateHomeserver,
      this.homeserverError,
      this.credentialsError});
  final bool canNavigateBack;
  final bool isLoggingIn;
  final bool? homeserverChecked;
  final double? progress;
  final List<LoginFlow>? flows;
  final bool loadingServerInfo;
  final bool isServerValid;
  final bool hasSsoSupport;
  final bool hasOidcSupport;
  final bool hasPasswordSupport;
  final Future<void> Function(SsoLoginFlow flow)? doSsoLogin;
  final Future<void> Function(OidcLoginFlow flow)? doOidcLogin;
  final Future<void> Function(
          PasswordLoginFlow flow, String username, String password)?
      doPasswordLogin;

  /// Vommet (Vommet issue 254): opens "Create an account"; resolves to a
  /// homeserver to fill in when the user chose to sign in there instead.
  final Future<String?> Function()? onCreateAccount;

  final Function(String)? updateHomeserver;

  final String? homeserverError;
  final String? credentialsError;

  @override
  State<LoginPageView> createState() => _LoginPageViewState();

  /// Vommet: the server name from a full Matrix ID typed as the username
  /// (`@alice:example.org` → `example.org`), or null for a plain username.
  static String? homeserverFromUserId(String input) {
    final match = RegExp(r'^@?[^:@\s]+:([^\s/]+)$').firstMatch(input.trim());
    final server = match?.group(1);
    if (server == null) return null;
    // Wait until it looks like a host name (or host:port), not "example".
    if (!server.contains('.') && !server.contains(':')) return null;
    if (server.endsWith('.') || server.endsWith(':')) return null;
    return server;
  }

  /// Vommet: the homeserver to fill in when [username] is a full Matrix ID,
  /// or null to leave the field alone. A homeserver the user typed
  /// themselves (e.g. matrix.example.org for @alice:example.org on a server
  /// without .well-known) is kept: only an empty field, the default, or what
  /// was filled in before ([autoFilled]) is replaced.
  static String? homeserverToFill(
      {required String username,
      required String currentHomeserver,
      required String defaultHomeserver,
      String? autoFilled}) {
    final server = homeserverFromUserId(username);
    if (server == null || server == currentHomeserver) return null;

    final userTyped = currentHomeserver.isNotEmpty &&
        currentHomeserver != defaultHomeserver &&
        currentHomeserver != autoFilled;
    return userTyped ? null : server;
  }
}

class _LoginPageViewState extends State<LoginPageView> {
  final TextEditingController _homeserverTextField = TextEditingController(
    text: GlobalConfig.defaultHomeserver,
  );
  final TextEditingController _usernameTextField = TextEditingController();
  final TextEditingController _passwordTextField = TextEditingController();

  String get promptHomeserver => Intl.message("Homeserver",
      name: "promptHomeserver",
      desc: "Placeholder text for homeserver field on login form");

  String get homeserverInsecureWarning => Intl.message(
      "Not encrypted: your password and messages travel unprotected to this server.",
      name: "homeserverInsecureWarning",
      desc:
          "Shown under the homeserver field on the login form when the user typed a plain http:// address that isn't on this device");

  String get promptUsername => Intl.message("Username",
      name: "promptUsername",
      desc: "Placeholder text for username field on login form");

  String get promptPassword => Intl.message("Password",
      name: "promptPassword",
      desc: "Placeholder text for password field on login form");

  String get promptSubmitLogin => Intl.message("Login",
      name: "promptSubmitLogin",
      desc: "Prompt to submit the username and password, and attempt to login");

  String get promptShowPasswordLogin => Intl.message(
      "Sign in with a password instead",
      name: "promptShowPasswordLogin",
      desc:
          "Link on the login form that reveals the username and password fields when the homeserver offers single sign-on");

  String get promptContinueOidcLogin => Intl.message("Continue",
      name: "promptContinueOidcLogin",
      desc:
          "Button on the login form that opens the homeserver's sign-in page in the browser (native OIDC sign-in)");

  String get promptHidePasswordLogin => Intl.message(
      "Sign in with your browser instead",
      name: "promptHidePasswordLogin",
      desc:
          "Link on the login form that hides the username and password fields and goes back to browser sign-in (single sign-on)");

  // Vommet: when the homeserver offers single sign-on, the username/password
  // form stays hidden behind a link (as in Element X), so SSO users see one
  // "Continue with …" button; password login remains one tap away for bot or
  // service accounts.
  bool showPasswordLogin = false;

  // Native OIDC (#45) replaces the SSO buttons with one "Continue", as in
  // Element X.
  bool get hasBrowserLogin => widget.hasSsoSupport || widget.hasOidcSupport;

  bool get passwordFormVisible =>
      widget.hasPasswordSupport && (!hasBrowserLogin || showPasswordLogin);

  @override
  void initState() {
    if (_homeserverTextField.text != "") {
      WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
        _onHomeserverTextUpdated();
      });
    }
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 0, sigmaY: 0),
            child: const StarTrailsBackground(),
          ),
          SafeArea(
            child: Stack(
              children: [
                Scaffold(
                  backgroundColor: Colors.transparent,
                  body: Material(
                    color: Colors.transparent,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Stack(
                        children: [
                          loginField(context),
                        ],
                      ),
                    ),
                  ),
                ),
                if (widget.canNavigateBack)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Align(
                        alignment: Alignment.topLeft,
                        child: CircleButton(
                          radius: 25,
                          icon: Icons.arrow_back,
                          onPressed: () => Navigator.of(context).pop(),
                        )),
                  ),
              ],
            ),
          ),
          SafeArea(
            child: Align(
                alignment: Alignment.topRight,
                child: SizedBox(
                    height: 30,
                    width: 30,
                    child: tiamat.IconButton(
                      icon: Icons.settings,
                      onPressed: () => NavigationUtils.navigateTo(
                          context, const AppSettingsPage()),
                    ))),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                  0, 0, 0, MediaQuery.of(context).padding.bottom),
              child: SettingsCategoryAbout.info(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget loginField(BuildContext context) {
    return Stack(
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Container(
              decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: Theme.of(context).colorScheme.surfaceContainer,
                  border: Border.all(
                      color: Theme.of(context).colorScheme.outline, width: 1),
                  boxShadow: [
                    BoxShadow(
                        blurRadius: 50,
                        color: Theme.of(context).shadowColor.withAlpha(50))
                  ]),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: Stack(
                  children: [
                    IgnorePointer(
                      ignoring: widget.isLoggingIn,
                      child: AnimatedOpacity(
                          opacity: widget.isLoggingIn ? 0.5 : 1.0,
                          duration: Durations.short2,
                          child: loginInputs(context)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (widget.isLoggingIn)
          const Center(
            child: CircularProgressIndicator(),
          )
      ],
    );
  }

  Widget loginInputs(BuildContext context) {
    var oidcFlow = widget.flows?.whereType<OidcLoginFlow>().firstOrNull;
    var ssoFlows = oidcFlow != null
        ? null
        : widget.flows?.whereType<SsoLoginFlow>().toList();
    SsoLoginFlow? defaultSso;
    if (ssoFlows != null) {
      defaultSso = ssoFlows.where((e) => e.id == null).firstOrNull;
    }

    return Column(mainAxisSize: MainAxisSize.min, children: [
      Flexible(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            appIcon(context),
          ],
        ),
      ),
      const SizedBox(height: 16),
      homeserverEntry(),
      const SizedBox(height: 16),
      if (passwordFormVisible) usenamePasswordLoginInputs(),
      if (hasBrowserLogin)
        Flexible(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Vommet: one sign-in path at a time. With the password form
              // open, the browser buttons hide, so "Login" is the only main
              // button; the link below switches back.
              if (!passwordFormVisible && oidcFlow != null)
                SizedBox(
                  height: 50,
                  child: tiamat.Button(
                    text: promptContinueOidcLogin,
                    onTap: () => widget.doOidcLogin?.call(oidcFlow),
                  ),
                ),
              if (!passwordFormVisible && defaultSso != null)
                tiamat.Button.secondary(
                  text: "Login with " + defaultSso.name,
                  onTap: () => {widget.doSsoLogin?.call(defaultSso!)},
                ),
              if (!passwordFormVisible && ssoFlows != null)
                Flexible(
                    child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: 10,
                    children: ssoFlows
                        .whereType<SsoLoginFlow>()
                        .where((e) => e != defaultSso)
                        .map((e) => ElevatedButton.icon(
                              icon: SizedBox(
                                  width: e.icon == null ? 0 : 32,
                                  height: 48,
                                  child: e.icon != null
                                      ? Image(image: e.icon!)
                                      : null),
                              label: Text("Continue with ${e.name}"),
                              onPressed: () => widget.doSsoLogin?.call(e),
                            ))
                        .toList(),
                  ),
                )),
              if (widget.hasPasswordSupport)
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 8, 0, 0),
                  child: TextButton(
                    onPressed: widget.isLoggingIn
                        ? null
                        : () => setState(
                            () => showPasswordLogin = !showPasswordLogin),
                    child: Text(showPasswordLogin
                        ? promptHidePasswordLogin
                        : promptShowPasswordLogin),
                  ),
                ),
            ],
          ),
        ),
      SizedBox(
        height: 15,
        child: Center(
          child: SizedBox(
            height: 5,
            child: widget.progress == null
                ? null
                : LinearProgressIndicator(
                    value: widget.progress,
                  ),
          ),
        ),
      ),
      if (widget.onCreateAccount != null) createAccountLink(),
    ]);
  }

  Widget usenamePasswordLoginInputs() {
    // Vommet (Vommet issue 305): one autofill group so password managers can
    // fill both fields. Saving is offered by LoginPage only after a
    // successful sign-in; leaving or hiding the form discards the entry.
    return AutofillGroup(
      onDisposeAction: AutofillContextAction.cancel,
      child: Column(
        children: [
          usernameEntry(),
          const SizedBox(height: 16),
          passwordEntry(),
          const SizedBox(height: 16),
          loginButton(),
        ],
      ),
    );
  }

  Text appName() {
    return const Text(
      "Vommet",
      style: TextStyle(fontFamily: 'Jellee', fontSize: 30),
    );
  }

  SizedBox loginButton() {
    var flow = widget.flows?.whereType<PasswordLoginFlow>().firstOrNull;

    return SizedBox(
      width: double.infinity,
      height: 50,
      child: tiamat.Button(
        text: promptSubmitLogin,
        onTap: flow != null
            ? () => widget.doPasswordLogin
                ?.call(flow, _usernameTextField.text, _passwordTextField.text)
            : null,
      ),
    );
  }

  /// The server we last filled in from a typed Matrix ID.
  String? _autoFilledHomeserver;

  void _onUsernameChanged(String value) {
    final server = LoginPageView.homeserverToFill(
        username: value,
        currentHomeserver: _homeserverTextField.text,
        defaultHomeserver: GlobalConfig.defaultHomeserver,
        autoFilled: _autoFilledHomeserver);
    if (server == null) return;

    _autoFilledHomeserver = server;
    _homeserverTextField.text = server;
    _onHomeserverTextUpdated();
  }

  TextField passwordEntry() {
    return TextField(
      autocorrect: false,
      controller: _passwordTextField,
      obscureText: true,
      autofillHints: const [AutofillHints.password],
      readOnly: widget.isLoggingIn,
      decoration: InputDecoration(
        border: const OutlineInputBorder(),
        labelText: promptPassword,
        errorText: widget.credentialsError,
        errorMaxLines: 2,
      ),
    );
  }

  TextField usernameEntry() {
    return TextField(
      autocorrect: false,
      controller: _usernameTextField,
      enableSuggestions: false,
      onChanged: _onUsernameChanged,
      readOnly: widget.isLoggingIn,
      inputFormatters: [FilteringTextInputFormatter.deny(RegExp("[ ]"))],
      autofillHints: const [AutofillHints.username],
      decoration: InputDecoration(
        border: const OutlineInputBorder(),
        labelText: promptUsername,
      ),
    );
  }

  Widget homeserverEntry() {
    return TextField(
      autocorrect: false,
      controller: _homeserverTextField,
      enableSuggestions: false,
      readOnly: widget.isLoggingIn,
      onChanged: widget.updateHomeserver,
      keyboardType: TextInputType.url,
      inputFormatters: [FilteringTextInputFormatter.deny(RegExp("[ ]"))],
      decoration: InputDecoration(
          // Vommet: a typed http:// or https:// replaces the prefix.
          prefixText: homeserverInputHasScheme(_homeserverTextField.text)
              ? null
              : 'https://',
          border: const OutlineInputBorder(),
          labelText: promptHomeserver,
          errorText: widget.loadingServerInfo ? null : widget.homeserverError,
          errorMaxLines: 2,
          // Vommet: plain http:// off this device gets a warning line.
          helperText:
              _homeserverIsInsecure() ? homeserverInsecureWarning : null,
          helperMaxLines: 2,
          helperStyle: const TextStyle(color: Colors.amber),
          suffix: homeserverEntrySuffix()),
    );
  }

  bool _homeserverIsInsecure() {
    final uri = homeserverUriFromInput(_homeserverTextField.text);
    return uri != null && homeserverUriIsInsecure(uri);
  }

  Widget homeserverEntrySuffix() {
    if (widget.loadingServerInfo) {
      return const SizedBox(
          width: 15,
          height: 15,
          child: CircularProgressIndicator(
            strokeWidth: 2,
          ));
    }

    return Icon(
      widget.isServerValid ? Icons.check : Icons.close,
      size: 15,
      color: widget.isServerValid ? Colors.greenAccent : Colors.redAccent,
    );
  }

  SizedBox appIcon(BuildContext context) {
    return SizedBox(
      width: 50,
      height: 50,
      child: SvgPicture.asset(
        "assets/images/app_icon/icon.svg",
        theme: SvgTheme(currentColor: Theme.of(context).colorScheme.onSurface),
      ),
    );
  }

  void _onHomeserverTextUpdated() {
    if (widget.updateHomeserver != null) {
      widget.updateHomeserver?.call(_homeserverTextField.text);
    }
  }

  // Vommet (Vommet issue 254).
  Widget createAccountLink() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 12),
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text("New to Matrix?",
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
          TextButton(
            onPressed: widget.isLoggingIn
                ? null
                : () async {
                    var server = await widget.onCreateAccount!();
                    if (server == null || !mounted) return;
                    _homeserverTextField.text = server;
                    _onHomeserverTextUpdated();
                  },
            child: const Text("Create an account"),
          ),
        ],
      ),
    );
  }
}
