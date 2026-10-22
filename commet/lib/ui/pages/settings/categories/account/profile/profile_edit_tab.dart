import 'dart:typed_data';

import 'package:commet/client/client.dart';
import 'package:commet/client/client_manager.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/organisms/user_profile/user_profile.dart';
import 'package:commet/utils/current_account.dart';
import 'package:flutter/widgets.dart';
import 'package:tiamat/tiamat.dart';

class ProfileEditTab extends StatefulWidget {
  const ProfileEditTab(
      {required this.clientManager, this.selectedClientIndex, super.key});
  final ClientManager clientManager;

  /// Account to open on; the current account (see [currentAccount]) if null.
  final int? selectedClientIndex;
  @override
  State<ProfileEditTab> createState() => _ProfileEditTabState();
}

class _ProfileEditTabState extends State<ProfileEditTab> {
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
    // Every account's profile is listed; the current one comes first.
    final clients = currentAccountFirst(
        widget.clientManager.clients, selectedClient?.identifier);
    return ListView.builder(
      shrinkWrap: true,
      physics: NeverScrollableScrollPhysics(),
      itemBuilder: (context, index) {
        var client = clients[index];
        return Column(
          children: [
            UserProfile(
              userId: client.self!.identifier,
              client: client,
              maxBioHeight: double.infinity,
            ),
            const Seperator()
          ],
        );
      },
      itemCount: clients.length,
    );
  }

  void pickAvatar(Client client, Uint8List bytes, String? type) async {
    await client.setAvatar(bytes, type ?? "");
    setState(() {});
  }

  void setDisplayName(Client client, String name) async {
    await client.setDisplayName(name);
  }
}
