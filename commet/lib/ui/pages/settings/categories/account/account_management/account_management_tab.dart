import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/client/client_manager.dart';
import 'package:commet/client/components/profile/profile_component.dart';
import 'package:commet/client/error_profile.dart';
import 'package:commet/client/components/account_switch_prefix/account_switch_prefix.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/support/homeserver_support.dart';
import 'package:commet/client/stale_info.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/molecules/user_panel.dart';
import 'package:commet/ui/navigation/adaptive_text_dialog.dart';
import 'package:commet/ui/pages/login/login_page.dart';
import 'package:commet/utils/links/link_utils.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:just_the_tooltip/just_the_tooltip.dart';
import 'package:provider/provider.dart';
import 'package:tiamat/tiamat.dart' as tiamat;
import 'package:tiamat/tiamat.dart';

class AccountManagementSettingsTab extends StatefulWidget {
  const AccountManagementSettingsTab({super.key, required this.clientManager});
  static ValueKey addAccountKey =
      const ValueKey("ACCOUNT_MANAGEMENT_SETTINGS_ADD_ACCOUNT_BUTTON");
  final ClientManager clientManager;
  @override
  State<AccountManagementSettingsTab> createState() =>
      _AccountManagementSettingsTabState();
}

class _AccountManagementSettingsTabState
    extends State<AccountManagementSettingsTab> {
  StreamSubscription<int>? onClientAddedListener;
  StreamSubscription<StalePeerInfo>? onClientRemovedListener;
  final GlobalKey<AnimatedListState> _listKey = GlobalKey<AnimatedListState>();
  late int _numClients;

  String get promptAddAccount => Intl.message("Add Account",
      desc: "Label for button in settings to add another account",
      name: "promptAddAccount");

  String get promptLogoutSingleAccount => Intl.message("Logout",
      desc: "Label for button in settings to log out of an account",
      name: "promptLogoutSingleAccount");

  String labelAccountFailedToLoad(String reason) => Intl.message(
      "Couldn't load this account: $reason",
      desc:
          "Shown under an account in the account list when it failed to load, with the error. Logout removes it",
      args: [reason],
      name: "labelAccountFailedToLoad");

  String get labelCurrentAccountsHeader => Intl.message("Current Accounts",
      desc: "Label for header of accounts list",
      name: "labelCurrentAccountsHeader");

  String get labelYourHomeserverHeader => Intl.message("Your homeserver",
      desc:
          "Header of the settings panel showing the support page and admin contacts that the user's homeserver publishes",
      name: "labelYourHomeserverHeader");

  String promptSupportHomeserver(String server) => Intl.message(
      "Support $server",
      args: [server],
      desc:
          "Button that opens the support (or donation) page published by the user's homeserver",
      name: "promptSupportHomeserver");

  String get labelHomeserverContactAdmin => Intl.message("Admin",
      desc:
          "Role of a homeserver contact (from the server's support file): the server administrator",
      name: "labelHomeserverContactAdmin");

  String get labelHomeserverContactModerator => Intl.message("Moderator",
      desc:
          "Role of a homeserver contact (from the server's support file): a moderator",
      name: "labelHomeserverContactModerator");

  String get labelHomeserverContactSecurity => Intl.message("Security",
      desc:
          "Role of a homeserver contact (from the server's support file): who to report security issues to",
      name: "labelHomeserverContactSecurity");

  String get labelHomeserverContactOther => Intl.message("Contact",
      desc:
          "Role of a homeserver contact (from the server's support file) whose role the app doesn't know",
      name: "labelHomeserverContactOther");

  /// Per server name: what it publishes at /.well-known/matrix/support.
  /// Keyed by server so two accounts on one server fetch (and show) it once.
  final Map<String, Future<HomeserverSupport?>> _support = {};

  String? _supportPanelKey;
  Future<List<(MatrixClient, String, HomeserverSupport?)>>? _supportPanelFuture;

  @override
  Widget build(BuildContext context) {
    return manageAccountsTab(context);
  }

  @override
  void initState() {
    onClientAddedListener =
        widget.clientManager.onClientAdded.stream.listen((index) {
      _listKey.currentState?.insertItem(index);
      setState(() {
        _numClients++;
      });
    });

    onClientRemovedListener =
        widget.clientManager.onClientRemoved.stream.listen((info) {
      _listKey.currentState?.removeItem(
          info.index,
          (context, animation) => SizeTransition(
                sizeFactor: animation,
                child: accountListItem(
                    displayName: info.displayName!,
                    avatar: info.avatar,
                    detail: info.identifier),
              ));
      setState(() {});
    });

    _numClients = widget.clientManager.clients.length;

    super.initState();
  }

  @override
  void dispose() {
    onClientAddedListener?.cancel();
    onClientRemovedListener?.cancel();
    super.dispose();
  }

  Widget manageAccountsTab(BuildContext context) {
    ClientManager clientManager = Provider.of<ClientManager>(context);

    return Align(
      alignment: Alignment.topCenter,
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Panel(
              header: labelCurrentAccountsHeader,
              mode: TileType.surfaceContainerLow,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  accountListBuilder(context, clientManager),
                  addAccountButton(context)
                ],
              ),
            ),
            homeserverSupportPanel(clientManager),
          ],
        ),
      ),
    );
  }

  /// Shown only when at least one account's server publishes support info.
  Widget homeserverSupportPanel(ClientManager clientManager) {
    // One entry per server, fetched through its first logged-in account.
    final servers = <String, MatrixClient>{};
    for (final client in clientManager.clients.whereType<MatrixClient>()) {
      final server =
          HomeserverSupport.serverNameOf(client.getMatrixClient().userID);
      if (server != null) servers.putIfAbsent(server, () => client);
    }
    if (servers.isEmpty) return const SizedBox.shrink();

    final key = servers.keys.join(",");
    if (key != _supportPanelKey) {
      _supportPanelKey = key;
      _supportPanelFuture = Future.wait(servers.entries.map((e) async => (
            e.value,
            e.key,
            await _support.putIfAbsent(
                e.key, () => HomeserverSupport.fetch(e.value))
          )));
    }

    return FutureBuilder<List<(MatrixClient, String, HomeserverSupport?)>>(
      future: _supportPanelFuture,
      builder: (context, snapshot) {
        final data = snapshot.data ??
            const <(MatrixClient, String, HomeserverSupport?)>[];
        final entries = [
          for (final (client, server, support) in data)
            if (support != null) (client, server, support),
        ];
        if (entries.isEmpty) return const SizedBox.shrink();

        return Panel(
          header: labelYourHomeserverHeader,
          mode: TileType.surfaceContainerLow,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (client, server, support) in entries)
                homeserverSupportItem(client, server, support),
            ],
          ),
        );
      },
    );
  }

  String contactRoleLabel(String role) => switch (role) {
        "m.role.admin" => labelHomeserverContactAdmin,
        "m.role.moderator" => labelHomeserverContactModerator,
        "m.role.security" => labelHomeserverContactSecurity,
        _ => labelHomeserverContactOther,
      };

  Widget homeserverSupportItem(
      MatrixClient client, String server, HomeserverSupport support) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (support.supportPage != null)
            tiamat.Button.secondary(
              text: promptSupportHomeserver(server),
              onTap: () => LinkUtils.open(support.supportPage!,
                  clientId: client.identifier, context: context),
            )
          else
            tiamat.Text.labelEmphasised(server),
          for (final contact in support.contacts)
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 4, 0, 0),
              child: tiamat.Text.labelLow([
                contactRoleLabel(contact.role),
                if (contact.matrixId != null) contact.matrixId!,
                if (contact.emailAddress != null) contact.emailAddress!,
              ].join(" · ")),
            ),
        ],
      ),
    );
  }

  Widget accountListBuilder(BuildContext context, ClientManager clientmanager) {
    var clients = clientmanager.clients;

    return AnimatedList(
      initialItemCount: _numClients,
      shrinkWrap: true,
      key: _listKey,
      itemBuilder: (context, index, animation) {
        return SizeTransition(
          sizeFactor: animation,
          child: accountListItem(
              client: clients[index],
              displayName: clients[index].self!.displayName,
              avatar: clients[index].self!.avatar,
              detail: accountDetail(clients[index].self!),
              internalId: clients[index].identifier,
              onLogoutClicked: () =>
                  clientmanager.logoutClient(clients[index])),
        );
      },
    );
  }

  String accountDetail(Profile self) {
    if (self is ErrorProfile && self.reason != null) {
      return labelAccountFailedToLoad(self.reason!);
    }
    return self.identifier;
  }

  Widget accountListItem(
      {required String displayName,
      Client? client,
      ImageProvider? avatar,
      String? detail,
      String? internalId,
      Function? onLogoutClicked}) {
    String detailString = detail ?? "";

    if (preferences.developerMode.value && internalId != null) {
      detailString = "$detail - ($internalId)";
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(8.0, 4, 12, 4),
      child: Material(
        color: Colors.transparent,
        clipBehavior: Clip.hardEdge,
        borderRadius: BorderRadius.circular(8),
        child: tiamat.ContextMenu(
          modal: true,
          items: client == null
              ? []
              : [
                  if (_numClients > 1)
                    tiamat.ContextMenuItem(
                        text: "Set Prefix",
                        onPressed: () {
                          setPrefixDialog(client);
                        })
                ],
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    UserPanelView(
                      displayName: displayName,
                      avatar: avatar,
                      detail: detailString,
                    ),
                  ],
                ),
              ),
              tiamat.Button.danger(
                text: promptLogoutSingleAccount,
                onTap: () {
                  onLogoutClicked?.call();
                },
              )
            ],
          ),
        ),
      ),
    );
  }

  Future<void> setPrefixDialog(Client client) async {
    final component = client.getComponent<AccountSwitchPrefix>();

    if (component == null) {
      return;
    }

    final newPrefix = await AdaptiveTextDialog.show(
        title: "Set Prefix",
        placeholder: "Enter Prefix",
        description:
            "When more than one of your logged in accounts share the same room, you can type this prefix to quickly send messages from this account",
        context,
        defaultText: component.clientPrefix);
    if (newPrefix == null) {
      return;
    }

    component.setClientPrefix(newPrefix);
  }

  Padding addAccountButton(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 8, 12, 12),
      child: Align(
          alignment: Alignment.centerRight,
          child: JustTheTooltip(
            content: Padding(
              padding: const EdgeInsets.all(8.0),
              child: tiamat.Text(promptAddAccount),
            ),
            preferredDirection: AxisDirection.down,
            offset: 5,
            tailLength: 5,
            tailBaseWidth: 5,
            backgroundColor:
                Theme.of(context).colorScheme.surfaceContainerLowest,
            child: tiamat.CircleButton(
              key: AccountManagementSettingsTab.addAccountKey,
              icon: Icons.add,
              radius: 20,
              onPressed: () {
                Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => LoginPage(
                          canNavigateBack: true,
                          onSuccess: (
                            _,
                          ) {
                            Navigator.of(context).pop();
                          },
                        )));
              },
            ),
          )),
    );
  }
}
