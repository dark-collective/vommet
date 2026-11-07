import 'package:commet/client/client.dart';
import 'package:flutter/material.dart';

/// Account identity shared by the Home chooser and the opened saved list.
class SavedMessagesAccount extends StatelessWidget {
  const SavedMessagesAccount({super.key, required this.client, this.onTap});

  final Client client;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final self = client.self;
    final id = self?.identifier ?? client.identifier;
    return ListTile(
      key: ValueKey('saved-account-${client.identifier}'),
      leading: CircleAvatar(
        backgroundColor: self?.defaultColor,
        foregroundImage: self?.avatar,
        child: const Icon(Icons.person_outline),
      ),
      title: Text(self?.displayName ?? id),
      subtitle: Text(id),
      trailing: onTap == null ? null : const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
