import 'package:commet/client/auth.dart';
import 'package:commet/client/client.dart';
import 'package:commet/client/matrix/auth/matrix_oidc_login_flow.dart';
import 'package:commet/client/matrix/auth/matrix_registration.dart';
import 'package:commet/client/matrix/auth/recommended_homeservers.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/ui/molecules/browser_sign_in_panel.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/utils/links/link_utils.dart';
import 'package:commet/utils/rng.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

// Vommet (Vommet issue 254): "Create an account" for people new to Matrix.
// Three short tutorial cards, the homeservers recommended on nether.wiki,
// then sign-up on the chosen server. The new account goes through the same
// post-login setup as a sign-in.

/// What the create-account screens hand back to the login page.
sealed class CreateAccountResult {}

/// An account was made and is signed in on [client].
class CreateAccountSignedUp extends CreateAccountResult {
  final Client client;
  CreateAccountSignedUp(this.client);
}

/// The user wants to sign in to [server] instead.
class CreateAccountSignIn extends CreateAccountResult {
  final String server;
  CreateAccountSignIn(this.server);
}

const _wikiHomeservers = "https://nether.wiki/matrix/homeservers/";
const _wikiEncryption = "https://nether.wiki/matrix/encryption/";
const _elementWebRegister = "https://app.element.io/#/register";

enum _Step { tutorial, picker, server }

class CreateAccountPage extends StatefulWidget {
  const CreateAccountPage({super.key});

  @override
  State<CreateAccountPage> createState() => _CreateAccountPageState();
}

class _CreateAccountPageState extends State<CreateAccountPage> {
  _Step step = _Step.tutorial;
  int tutorialPage = 0;

  List<RecommendedHomeserver>? servers;
  RecommendedHomeserver? selected;

  /// Set once the user says they have an invite for an invite-only server.
  bool hasInvite = false;

  MatrixClient? client;
  bool detecting = false;
  bool busy = false;
  RegistrationMethod? method;
  String? error;

  final usernameField = TextEditingController();
  final passwordField = TextEditingController();
  final confirmField = TextEditingController();
  final tokenField = TextEditingController();
  bool termsAccepted = false;

  @override
  void initState() {
    super.initState();
    RecommendedHomeserver.load().then((list) {
      if (mounted) setState(() => servers = list);
    }).catchError((Object e, StackTrace t) {
      Log.onError(e, t);
      if (mounted) setState(() => servers = []);
    });
    MatrixClient.create(RandomUtils.getRandomString(20)).then((c) {
      client = c;
    });
  }

  @override
  void dispose() {
    usernameField.dispose();
    passwordField.dispose();
    confirmField.dispose();
    tokenField.dispose();
    super.dispose();
  }

  void back() {
    if (step == _Step.tutorial && tutorialPage == 0) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      error = null;
      switch (step) {
        case _Step.tutorial:
          tutorialPage--;
        case _Step.picker:
          step = _Step.tutorial;
          tutorialPage = 2;
        case _Step.server:
          step = _Step.picker;
          method = null;
          hasInvite = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: step == _Step.tutorial && tutorialPage == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !busy) back();
      },
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    header(context),
                    const SizedBox(height: 8),
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: Durations.short4,
                        child: KeyedSubtree(
                          key: ValueKey((step, tutorialPage, selected)),
                          child: switch (step) {
                            _Step.tutorial => tutorial(context),
                            _Step.picker => picker(context),
                            _Step.server => serverStep(context),
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget header(BuildContext context) {
    final title = switch (step) {
      _Step.tutorial => "",
      _Step.picker => "Pick a homeserver",
      _Step.server => selected?.server ?? "",
    };
    return Row(
      children: [
        IconButton(
          tooltip: "Back",
          icon: const Icon(Icons.arrow_back),
          onPressed: busy ? null : back,
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(title,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium),
        ),
        if (step == _Step.tutorial)
          TextButton(
            onPressed: () => setState(() => step = _Step.picker),
            child: const Text("Skip"),
          ),
      ],
    );
  }

  // ---- Tutorial ----------------------------------------------------------

  Widget tutorial(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

    final (icon, title, body) = switch (tutorialPage) {
      0 => (
          Icons.alternate_email,
          "Your account lives on a server, like email",
          <Widget>[
            Text(
                "Matrix isn't run by one company. You pick a homeserver, and your name includes it:",
                style: TextStyle(color: muted)),
            const SizedBox(height: 12),
            idExample(context),
            const SizedBox(height: 12),
            Text(
                "You can still talk to anyone on any server. Your name can't move to another server later, so the next screens help you pick.",
                style: TextStyle(color: muted)),
          ]
        ),
      1 => (
          Icons.swap_horiz,
          "Coming from Discord? Same things, new names",
          <Widget>[
            discordMap(context),
            const SizedBox(height: 12),
            Text(
                "Friends on Element or other Matrix apps are in the same rooms and calls.",
                style: TextStyle(color: muted)),
          ]
        ),
      _ => (
          Icons.key,
          "Your messages are locked, and you hold the key",
          <Widget>[
            Text(
                "Private chats are end-to-end encrypted. Right after sign-up, Vommet gives you a recovery key. Save it in a password manager: without it, a new phone can't read your old messages, and nobody can recover them for you.",
                style: TextStyle(color: muted)),
            const SizedBox(height: 12),
            linkText(context, "More about encryption on nether.wiki",
                Uri.parse(_wikiEncryption)),
          ]
        ),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 16),
                Icon(icon, size: 48, color: theme.colorScheme.primary),
                const SizedBox(height: 12),
                Text(title, style: theme.textTheme.headlineSmall),
                const SizedBox(height: 12),
                ...body,
              ],
            ),
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          spacing: 6,
          children: [
            for (var i = 0; i < 3; i++)
              AnimatedContainer(
                duration: Durations.short4,
                width: i == tutorialPage ? 18 : 7,
                height: 7,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  color: i == tutorialPage
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outlineVariant,
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 48,
          child: tiamat.Button(
            text: tutorialPage < 2 ? "Next" : "Pick a server",
            onTap: () => setState(() {
              if (tutorialPage < 2) {
                tutorialPage++;
              } else {
                step = _Step.picker;
              }
            }),
          ),
        ),
      ],
    );
  }

  Widget idExample(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: Text.rich(
        TextSpan(children: [
          const TextSpan(text: "@sunny"),
          TextSpan(
              text: ":tchncs.de",
              style: TextStyle(color: theme.colorScheme.primary)),
        ]),
        style: const TextStyle(fontFamily: "monospace", fontSize: 15),
      ),
    );
  }

  Widget discordMap(BuildContext context) {
    final theme = Theme.of(context);
    const rows = [
      ("Server", "Space"),
      ("Channel", "Room"),
      ("Activities", "Widgets"),
      ("Nitro", "Free, nobody to pay"),
      ("Trust & Safety", "Your server's admins"),
    ];
    final label = theme.textTheme.labelSmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Table(
        columnWidths: const {
          0: FlexColumnWidth(),
          1: IntrinsicColumnWidth(),
          2: FlexColumnWidth(),
        },
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: [
          TableRow(children: [
            Text("DISCORD", style: label),
            const SizedBox(width: 24),
            Text("MATRIX", style: label),
          ]),
          for (final (discord, matrix) in rows)
            TableRow(children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(discord),
              ),
              Icon(Icons.arrow_forward,
                  size: 14, color: theme.colorScheme.onSurfaceVariant),
              Text(matrix, style: const TextStyle(fontWeight: FontWeight.bold)),
            ]),
        ],
      ),
    );
  }

  // ---- Server picker -----------------------------------------------------

  Widget picker(BuildContext context) {
    final list = servers;
    final theme = Theme.of(context);
    if (list == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            children: [
              Text(
                  "Servers we recommend on nether.wiki. Any of them can talk to all the others.",
                  style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(height: 12),
              for (final server in list) ...[
                serverCard(context, server),
                const SizedBox(height: 8),
              ],
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                children: [
                  TextButton(
                    onPressed: () => pickOtherServer(context),
                    child: const Text("Other server…"),
                  ),
                  TextButton(
                    onPressed: () => LinkUtils.open(Uri.parse(_wikiHomeservers),
                        context: context, bypassConfirmation: true),
                    child: const Text("Why not matrix.org?"),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 48,
          child: tiamat.Button(
            text: selected == null
                ? "Pick a server"
                : "Continue with ${selected!.server}",
            onTap: selected == null ? null : () => openServer(selected!),
          ),
        ),
      ],
    );
  }

  Widget serverCard(BuildContext context, RecommendedHomeserver server) {
    final theme = Theme.of(context);
    final isSelected = selected?.server == server.server;

    return Material(
      color: theme.colorScheme.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: isSelected
              ? theme.colorScheme.primary
              : theme.colorScheme.outlineVariant,
          width: isSelected ? 2 : 1,
        ),
      ),
      child: InkWell(
        mouseCursor: WidgetStateMouseCursor.clickable,
        borderRadius: BorderRadius.circular(10),
        onTap: () => setState(() => selected = server),
        onDoubleTap: () => openServer(server),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 6,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(server.server,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold)),
                  ),
                  if (server.us)
                    chip(context, "this is us",
                        background: theme.colorScheme.primary,
                        foreground: theme.colorScheme.onPrimary),
                ],
              ),
              Text(server.summary,
                  style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  registrationChip(context, server),
                  server.calls
                      ? chip(context, "voice calls ✓",
                          foreground: Colors.green.shade400)
                      : chip(context, "no calls",
                          foreground: theme.colorScheme.error),
                  for (final tag in server.tags) chip(context, tag),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget registrationChip(BuildContext context, RecommendedHomeserver server) {
    return switch (server.registration) {
      HomeserverRegistration.open =>
        chip(context, "open", foreground: Colors.green.shade400),
      HomeserverRegistration.token =>
        chip(context, "needs a token", foreground: Colors.amber.shade400),
      HomeserverRegistration.invite =>
        chip(context, "invite only", foreground: Colors.amber.shade400),
    };
  }

  Widget chip(BuildContext context, String text,
      {Color? background, Color? foreground}) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background ?? theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(text,
          style: theme.textTheme.labelSmall?.copyWith(
              color: foreground ?? theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600)),
    );
  }

  Future<void> pickOtherServer(BuildContext context) async {
    final field = TextEditingController();
    final server = await AdaptiveDialog.show<String>(
      context,
      title: "Other server",
      builder: (dialogContext) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: field,
            autofocus: true,
            autocorrect: false,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              prefixText: "https://",
              border: OutlineInputBorder(),
              labelText: "Homeserver",
            ),
            onSubmitted: (v) => Navigator.of(dialogContext).pop(v.trim()),
          ),
          const SizedBox(height: 12),
          tiamat.Button(
            text: "Continue",
            onTap: () => Navigator.of(dialogContext).pop(field.text.trim()),
          ),
        ],
      ),
    );
    field.dispose();
    if (server == null || server.isEmpty) return;

    openServer(RecommendedHomeserver(
      server: server,
      summary: "",
      registration: HomeserverRegistration.open,
    ));
  }

  // ---- Sign-up on the chosen server --------------------------------------

  void openServer(RecommendedHomeserver server) {
    setState(() {
      selected = server;
      step = _Step.server;
      method = null;
      error = null;
      hasInvite = false;
      termsAccepted = false;
    });
    if (server.registration != HomeserverRegistration.invite) detect();
  }

  Future<void> detect() async {
    final server = selected;
    if (server == null) return;
    setState(() {
      detecting = true;
      error = null;
    });

    while (client == null) {
      await Future.delayed(const Duration(milliseconds: 50));
    }

    RegistrationMethod? result;
    String? problem;
    final uri = _serverUri(server.server);
    if (uri == null) {
      problem = "That doesn't look like a server address.";
    } else {
      final (found, _) = await client!.setHomeserver(uri);
      if (!found) {
        problem = "Couldn't find a Matrix server at ${server.server}.";
      } else {
        try {
          result = await detectRegistrationMethod(client!.getMatrixClient());
        } catch (e, t) {
          Log.onError(e, t);
          problem = "Couldn't ask ${server.server} how to sign up: $e";
        }
      }
    }

    if (!mounted || selected != server) return;
    setState(() {
      detecting = false;
      method = result;
      error = problem;
    });
  }

  Future<void> runFlow(LoginFlow flow) async {
    final c = client;
    if (c == null) return;
    setState(() {
      busy = true;
      error = null;
    });

    LoginResult result;
    try {
      result = await c.executeLoginFlow(flow);
    } catch (e, t) {
      Log.onError(e, t);
      result = LoginResultError(e.toString());
    }
    if (!mounted) return;

    if (result is LoginResultSuccess) {
      Navigator.of(context).pop(CreateAccountSignedUp(c));
      return;
    }

    setState(() {
      busy = false;
      error = switch (result) {
        LoginResultError e => e.errorMessage,
        LoginResultCancelled _ => null,
        LoginResultAlreadyLoggedIn _ =>
          "You're already signed in to this account.",
        _ => "Sign-up didn't finish. Try again.",
      };
    });
  }

  void signInInstead() {
    Navigator.of(context).pop(CreateAccountSignIn(selected?.server ?? ""));
  }

  Widget serverStep(BuildContext context) {
    final server = selected!;

    final List<Widget> content;
    if (server.registration == HomeserverRegistration.invite && !hasInvite) {
      content = inviteInfo(context, server);
    } else if (detecting || (method == null && error == null)) {
      content = [
        const SizedBox(height: 48),
        const Center(child: CircularProgressIndicator()),
      ];
    } else {
      content = switch (method) {
        RegistrationInBrowser _ => inBrowser(context, server),
        RegistrationInApp m => inApp(context, server, m),
        RegistrationUnsupported m => unsupported(context, server, m),
        RegistrationClosed _ => closed(context, server),
        null => [
            tiamat.Button.secondary(text: "Try again", onTap: detect),
          ],
      };
    }

    // The browser sign-in panel stays clickable while busy (to copy its link
    // or cancel); only the content above it is locked.
    return ListView(
      children: [
        IgnorePointer(
          ignoring: busy,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: content,
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: 12),
          Text(error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
        if (busy) ...[
          const SizedBox(height: 16),
          const Center(child: BrowserSignInPanel()),
        ],
      ],
    );
  }

  Widget note(BuildContext context, List<InlineSpan> spans) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text.rich(TextSpan(children: spans)),
    );
  }

  Widget linkText(BuildContext context, String text, Uri url) {
    return InkWell(
      mouseCursor: WidgetStateMouseCursor.clickable,
      onTap: () =>
          LinkUtils.open(url, context: context, bypassConfirmation: true),
      child: Text(text,
          style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              decoration: TextDecoration.underline)),
    );
  }

  Widget signInButton(RecommendedHomeserver server) {
    return tiamat.Button.secondary(
      text: "Sign in to ${server.server}",
      onTap: signInInstead,
    );
  }

  List<Widget> inviteInfo(BuildContext context, RecommendedHomeserver server) {
    return [
      note(context, [
        TextSpan(
            text: "${server.server} is invite-only. ",
            style: const TextStyle(fontWeight: FontWeight.bold)),
        TextSpan(
            text: server.registrationNote ??
                "You need an invite before you can create an account."),
      ]),
      if (server.infoUrl != null) ...[
        const SizedBox(height: 12),
        linkText(context, "How to get an invite", server.infoUrl!),
      ],
      const SizedBox(height: 12),
      Text(
          "No invite yet? You can make an account on an open server now and join the same public rooms from there.",
          style:
              TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      const SizedBox(height: 20),
      SizedBox(
        height: 48,
        child: tiamat.Button(
          text: "I have an invite",
          onTap: () {
            setState(() => hasInvite = true);
            detect();
          },
        ),
      ),
      const SizedBox(height: 8),
      tiamat.Button.secondary(
        text: "Pick a different server",
        onTap: back,
      ),
    ];
  }

  List<Widget> inBrowser(BuildContext context, RecommendedHomeserver server) {
    return [
      note(context, [
        TextSpan(
            text:
                "${server.server} creates accounts on its own page. Vommet opens it in your browser and signs you in when you're done."),
      ]),
      const SizedBox(height: 12),
      Text(
          "Your username can't be changed later. Your display name can, any time.",
          style:
              TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      const SizedBox(height: 20),
      SizedBox(
        height: 48,
        child: tiamat.Button(
          text: "Open sign-up page",
          onTap: () => runFlow(MatrixOidcLoginFlow(createAccount: true)),
        ),
      ),
      const SizedBox(height: 8),
      signInButton(server),
    ];
  }

  List<Widget> inApp(
      BuildContext context, RecommendedHomeserver server, RegistrationInApp m) {
    final policies = registrationPolicies(m.params);
    final domain = client?.getMatrixClient().homeserver?.host ?? server.server;

    return [
      AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 12,
          children: [
            TextField(
              controller: usernameField,
              autocorrect: false,
              autofillHints: const [AutofillHints.newUsername],
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: "Username",
                prefixText: "@",
                suffixText: ":${server.server}",
                helperText: "Permanent. Your display name can change later.",
              ),
            ),
            TextField(
              controller: passwordField,
              obscureText: true,
              autofillHints: const [AutofillHints.newPassword],
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: "Password",
              ),
            ),
            TextField(
              controller: confirmField,
              obscureText: true,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: "Password again",
              ),
            ),
            if (m.needsToken)
              TextField(
                controller: tokenField,
                autocorrect: false,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: "Registration token",
                  helperText: server.registrationNote,
                  helperMaxLines: 3,
                ),
              ),
          ],
        ),
      ),
      if (m.needsTerms) ...[
        const SizedBox(height: 8),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: termsAccepted,
          onChanged: (v) => setState(() => termsAccepted = v ?? false),
          title: Text("I accept $domain's terms"),
          subtitle: policies.isEmpty
              ? null
              : Wrap(
                  spacing: 12,
                  children: [
                    for (final (name, url) in policies)
                      linkText(context, name, url),
                  ],
                ),
        ),
      ],
      const SizedBox(height: 20),
      SizedBox(
        height: 48,
        child: tiamat.Button(
          text: "Create account",
          onTap: () => submitInApp(m),
        ),
      ),
      const SizedBox(height: 8),
      signInButton(server),
    ];
  }

  void submitInApp(RegistrationInApp m) {
    final username = usernameField.text.trim();
    final password = passwordField.text;
    String? problem;
    if (username.isEmpty) {
      problem = "Pick a username.";
    } else if (password.isEmpty) {
      problem = "Pick a password.";
    } else if (password != confirmField.text) {
      problem = "The two passwords don't match.";
    } else if (m.needsToken && tokenField.text.trim().isEmpty) {
      problem = "Enter the registration token.";
    } else if (m.needsTerms && !termsAccepted) {
      problem = "Accept the server's terms to continue.";
    }
    if (problem != null) {
      setState(() => error = problem);
      return;
    }

    runFlow(MatrixRegistrationFlow(
      method: m,
      username: username,
      password: password,
      token: tokenField.text.trim(),
      completeInBrowser: completeInBrowser,
    ));
  }

  Future<bool> completeInBrowser(String stage, Uri url) async {
    if (!mounted) return false;
    final what = stage == recaptchaStage ? "the captcha" : "this step";
    await LinkUtils.open(url,
        context: context,
        bypassConfirmation: true,
        filterTrackingParameters: false);
    if (!mounted) return false;

    final done = await AdaptiveDialog.show<bool>(
      context,
      title: "Finish in your browser",
      builder: (dialogContext) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text("Complete $what on the page that opened, then come back."),
          const SizedBox(height: 12),
          tiamat.Button(
            text: "I've finished",
            onTap: () => Navigator.of(dialogContext).pop(true),
          ),
          const SizedBox(height: 8),
          tiamat.Button.secondary(
            text: "Open the page again",
            onTap: () => LinkUtils.open(url,
                context: dialogContext,
                bypassConfirmation: true,
                filterTrackingParameters: false),
          ),
        ],
      ),
    );
    return done == true;
  }

  List<Widget> unsupported(BuildContext context, RecommendedHomeserver server,
      RegistrationUnsupported m) {
    final needsEmail = m.missingStages.contains("m.login.email.identity");
    final what = needsEmail ? "email verification" : "a sign-up step";
    return [
      note(context, [
        TextSpan(
            text:
                "${server.server}'s sign-up needs $what, which Vommet can't do yet. "),
        const TextSpan(
            text:
                "Create the account on the server's website or in Element Web, then come back and sign in."),
      ]),
      const SizedBox(height: 20),
      SizedBox(
        height: 48,
        child: tiamat.Button(
          text: "Open Element Web",
          onTap: () => LinkUtils.open(Uri.parse(_elementWebRegister),
              context: context, bypassConfirmation: true),
        ),
      ),
      const SizedBox(height: 8),
      signInButton(server),
    ];
  }

  List<Widget> closed(BuildContext context, RecommendedHomeserver server) {
    final invite = server.registration == HomeserverRegistration.invite;
    return [
      note(context, [
        TextSpan(
            text: invite
                ? "Create your account with the invite you were given, then sign in here. "
                : "${server.server} doesn't take sign-ups from apps. "),
        TextSpan(
            text: invite
                ? "The invite opens the page where you pick your username and password."
                : "If it has its own sign-up page, make the account there, then sign in."),
      ]),
      if (server.infoUrl != null) ...[
        const SizedBox(height: 12),
        linkText(context, "More about ${server.server}", server.infoUrl!),
      ],
      const SizedBox(height: 20),
      SizedBox(height: 48, child: signInButton(server)),
      const SizedBox(height: 8),
      tiamat.Button.secondary(
        text: "Pick a different server",
        onTap: back,
      ),
    ];
  }
}

/// The homeserver address the user typed, as a URL: https unless they gave
/// a scheme themselves.
Uri? _serverUri(String input) {
  final text = input.trim();
  if (text.isEmpty) return null;
  try {
    if (text.startsWith("https://") || text.startsWith("http://")) {
      final uri = Uri.parse(text);
      return uri.host.isEmpty ? null : uri;
    }
    return Uri.https(text);
  } on FormatException {
    return null;
  }
}
