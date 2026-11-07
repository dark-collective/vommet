End-to-end encryption protects a chat's contents so the homeserver relays encrypted messages instead of reading them. It does not hide everything: servers still handle information such as room membership. People who can read a message can also copy it or take a screenshot.

Not every room is encrypted. Public rooms and bridges may work differently, so check the room's status before sharing something private.

## What the icons after a room's name mean

[[picture: shield]]

No icon is the normal case: the room is encrypted and nothing needs your attention. An icon means something is different:

- **Gray**: this room isn't encrypted. That's normal for big public rooms.
- **Green**: you've verified the person in this direct message.
- **Amber**: this direct message isn't encrypted, often because it's a bot or a bridge.
- **Red**: the person's identity changed. If they didn't tell you they reset it, someone could be pretending to be them.

## Your password is not your recovery key

Your **account password** signs you in to your homeserver. Your **recovery key** unlocks the encrypted backup of your message keys. Vommet may instead help you save a recovery phrase or choose a separate recovery password. Keep whichever recovery method you set up somewhere private, such as a password manager.

Resetting your account password does not restore missing message keys. Do not send recovery material to someone offering help or post it in a chat. It is a secret, not a code to share with support.

A backup can restore the message keys saved in it. It does not guarantee access to every message ever sent in a room, including messages you were never allowed to read.

## Adding a new device

1. Keep a working device signed in while you set up the new one.
2. Sign in with the **same Matrix account**, not a newly created account. See [Matrix accounts](guide:accounts) if you are unsure which address to use.
3. Verify the new device using a trusted signed-in device, or enter the recovery method you saved. Compare verification emoji on both devices before confirming; reject a request you did not start.
4. Allow the backup to restore, then check that the messages you need open on the new device before signing out of the old one.

Your devices and recovery settings are in **Settings › Security**. To verify another person, open their profile and choose **Verify**, then compare the emoji with them.

## Lost your recovery method?

**A device still reads your messages:** keep it signed in. Do not clear its app data or reinstall it while troubleshooting. Open **Settings › Security › Encryption & recovery** and check your recovery setup. If you replace the recovery key from a working device, save the new recovery method and finish the confirmation steps before removing the old device.

**No usable device and no recovery method:** older encrypted messages may be unrecoverable. A homeserver administrator cannot reconstruct missing encryption keys. Starting over with a new recovery setup protects future messages; it does not unlock the old history.

## A message will not open

On a new device, finish verification and recovery first, and allow time for message keys to arrive. Some messages may not have been backed up or shared with this device, and room history rules may exclude messages from before you joined. A missing message does not by itself mean you need to reset encryption. Keep a working device available and ask for help without sharing your recovery secrets.
