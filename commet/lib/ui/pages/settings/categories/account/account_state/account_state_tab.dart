import 'package:commet/client/client.dart';
import 'package:commet/client/client_manager.dart';
import 'package:commet/main.dart';
import 'package:commet/utils/current_account.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';

import '../../../../../molecules/account_selector.dart';

class AccountStateTab extends StatefulWidget {
  const AccountStateTab(
      {required this.clientManager, this.selectedClientIndex, super.key});
  final ClientManager clientManager;

  /// Account to open on; the current account (see [currentAccount]) if null.
  final int? selectedClientIndex;
  @override
  State<AccountStateTab> createState() => _AccountStateTabState();
}

class _AccountStateTabState extends State<AccountStateTab> {
  Client? selectedClient;

  @override
  void initState() {
    final index = widget.selectedClientIndex;
    selectedClient = index != null
        ? widget.clientManager.clients[index]
        : currentAccount(
            widget.clientManager.clients, preferences.filterClient.value);
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (widget.clientManager.clients.length > 1)
          AccountSelector(
            widget.clientManager.clients,
            initialClient: selectedClient,
            onClientSelected: (client) {
              setState(() {
                selectedClient = client;
              });
            },
          ),
        selectedClient!.buildDebugInfo()
      ],
    );
  }
}
