Vommet is an app for **Matrix**, an open chat network. Your account lives on a server called a **homeserver**, a little like an email account lives with an email provider. Vommet is the app you use to reach it, not the provider of every account.

[[picture: accounts]]

## Your address stays with your homeserver

Your Matrix address includes your username and homeserver, like **@mossfox:example.org**. Your **display name** and avatar can change. Your Matrix address cannot be renamed or moved to another homeserver: choosing another provider means creating a different account.

You can sign in to the same account on more than one device or in another Matrix app. That is different from making a new account. Save your full address and account password so you can sign in again.

## Spaces, rooms and direct messages

- A **space** is a collection of rooms, roughly like a Discord server. Joining a space does not automatically join its rooms.
- A **room** is where a conversation happens, roughly like a channel. Some rooms need an invitation or approval to join.
- A **direct message** is a room used for a private conversation. It still belongs to Matrix, even if the other person uses a different app.

See [Spaces and rooms](guide:spaces) for how to find and join them.

## What federation means

People on different homeservers can exchange messages and share rooms. You do not need an account on every friend's homeserver.

Federation does not override a room's access rules or a server's moderation policy. An outage or a connection problem between servers can delay messages. Calls and other features also depend on what the apps and servers support; sharing Matrix addresses does not guarantee every feature works everywhere.

## Choosing an account

Some homeservers accept public registrations; others need an invite. Read the provider's rules before choosing. Vommet's **Create an account** path suggests servers and also lets you choose another one. These suggestions do not replace the provider's current registration rules.

You can use more than one account in **Settings › Manage Accounts**. Each has its own address and recovery setup.

## Before you rely on your new account

Your account password and your encrypted message history need different protection. Save your recovery method during secure messaging setup, and verify each new device. Read [Encryption and recovery](guide:encryption) before signing out of your last working device.
