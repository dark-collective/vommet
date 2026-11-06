import 'package:commet/client/client.dart';

/// The account the app is switched to: the one whose identifier is
/// [selectedId] (`preferences.filterClient`). Falls back to the first
/// account when showing all accounts, or when that account is gone.
Client? currentAccount(List<Client> clients, String? selectedId) {
  if (selectedId != null) {
    for (final client in clients) {
      if (client.identifier == selectedId) return client;
    }
  }
  return clients.firstOrNull;
}

/// [clients] with the account from [currentAccount] moved to the front, the
/// rest kept in order.
List<Client> currentAccountFirst(List<Client> clients, String? selectedId) {
  final current = currentAccount(clients, selectedId);
  if (current == null) return List.of(clients);
  return [current, ...clients.where((c) => c != current)];
}
