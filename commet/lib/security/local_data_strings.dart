// Vommet: local data encryption (opt-in, phase 6), the words of the
// first-run page, the notices, the start-up screens, the splash and
// Settings › Privacy › Data on this device.
import 'package:intl/intl.dart';

// First-run page.

String get localDataOnboardingTitle => Intl.message(
      "Encrypt Vommet's data on this device?",
      name: "localDataOnboardingTitle",
      desc:
          "Title of the first-run page asking whether the app should encrypt the messages, search and settings it stores on the device",
    );

String get localDataOnboardingBody => Intl.message(
      "It protects your messages, search and settings stored on this device if someone gets your files. The key is kept in your system keyring. You can change it later in Settings › Privacy.",
      name: "localDataOnboardingBody",
      desc: "Explanation under the title of the first-run encryption page",
    );

String get localDataChoiceNotNow => Intl.message(
      "Not now",
      name: "localDataChoiceNotNow",
      desc:
          "First-run page: the choice that keeps the data on the device unencrypted (the default)",
    );

String get localDataChoiceNotNowDescription => Intl.message(
      "Messages, search and settings stay unencrypted on this device. Media is always encrypted.",
      name: "localDataChoiceNotNowDescription",
      desc: "First-run page: description of the Not now choice",
    );

String get localDataChoiceEncrypt => Intl.message(
      "Encrypt",
      name: "localDataChoiceEncrypt",
      desc:
          "First-run page: the choice that encrypts the data on the device from the start",
    );

String get localDataChoiceEncryptDescription => Intl.message(
      "Messages, search and settings are encrypted from the start, with the key in your system keyring.",
      name: "localDataChoiceEncryptDescription",
      desc: "First-run page: description of the Encrypt choice",
    );

// Notice for existing users.

String get localDataOfferTitle => Intl.message(
      "You can now encrypt your messages on this device",
      name: "localDataOfferTitle",
      desc:
          "Title of a one-time notice telling existing users they can turn on encryption of the data stored on the device",
    );

String get localDataOfferBody => Intl.message(
      "It's off by default while it's new.",
      name: "localDataOfferBody",
      desc: "Body of the notice offering encryption of the data on the device",
    );

String get localDataOfferAction => Intl.message(
      "Set up",
      name: "localDataOfferAction",
      desc:
          "Button of the notice offering encryption of the data on the device; opens the settings",
    );

// The key is kept in a file.

String get localDataKeyFileNoticeTitle => Intl.message(
      "Your key is kept in a file",
      name: "localDataKeyFileNoticeTitle",
      desc:
          "Title of a notice shown once when no system keyring was found and the encryption key is kept in a file",
    );

String get localDataKeyFileNoticeBody => Intl.message(
      "Your messages on this device are encrypted, but no system keyring or password manager was found, so the key is kept in a file next to them.",
      name: "localDataKeyFileNoticeBody",
      desc: "Body of the notice saying the encryption key is kept in a file",
    );

String get localDataLearnMore => Intl.message(
      "Learn more",
      name: "localDataLearnMore",
      desc: "Button opening an explanation of where the encryption key is kept",
    );

String get localDataKeyFileDialogTitle => Intl.message(
      "Where your key is kept",
      name: "localDataKeyFileDialogTitle",
      desc: "Title of the dialog explaining where the encryption key is kept",
    );

String get localDataKeyFileDialogKeyring => Intl.message(
      "Vommet encrypts the messages, search index and media it keeps on this device. The key that opens them is normally kept in your system keyring, the password manager built into your desktop (like GNOME Keyring, KDE Wallet or KeePassXC).",
      name: "localDataKeyFileDialogKeyring",
      desc:
          "First paragraph of the dialog explaining where the encryption key is kept",
    );

String get localDataKeyFileDialogFile => Intl.message(
      "This computer doesn't have one running, so the key is kept in a file in Vommet's own folder. Copies of just the database (like a backup of only that file) stay unreadable. But anyone who can open your files can open the key too, so this doesn't protect against someone with access to this computer.",
      name: "localDataKeyFileDialogFile",
      desc:
          "Second paragraph of the dialog explaining where the encryption key is kept",
    );

String get localDataKeyFileDialogBetter => Intl.message(
      "For better protection, turn on a keyring or full-disk encryption. If a keyring shows up later, Vommet moves the key into it on its own.",
      name: "localDataKeyFileDialogBetter",
      desc:
          "Third paragraph of the dialog explaining where the encryption key is kept",
    );

String get localDataOpenSettings => Intl.message(
      "Open settings",
      name: "localDataOpenSettings",
      desc: "Button opening the settings about the data on the device",
    );

String get localDataGotIt => Intl.message(
      "Got it",
      name: "localDataGotIt",
      desc: "Button closing an explanation",
    );

// Start-up: the keyring is locked.

String get localDataLockedTitle => Intl.message(
      "Unlock your keyring to continue",
      name: "localDataLockedTitle",
      desc:
          "Title of the start-up screen shown while the system keyring holding the encryption key is locked",
    );

String get localDataLockedBody => Intl.message(
      "The key to your messages on this device is kept in your system keyring, and it's locked. Unlock it in the window your system opened, and Vommet will continue on its own.",
      name: "localDataLockedBody",
      desc: "Body of the start-up screen shown while the keyring is locked",
    );

String get localDataLockedWaiting => Intl.message(
      "Waiting for your keyring…",
      name: "localDataLockedWaiting",
      desc:
          "Status line of the start-up screen while it waits for the keyring to be unlocked",
    );

String get localDataLockedTip => Intl.message(
      "Tip: if your keyring's password is the same as your login password, it unlocks by itself when you sign in.",
      name: "localDataLockedTip",
      desc: "Tip on the start-up screen shown while the keyring is locked",
    );

String get localDataQuit => Intl.message(
      "Quit",
      name: "localDataQuit",
      desc: "Button closing the app from a start-up screen",
    );

String get localDataStillLockedTitle => Intl.message(
      "Your keyring is still locked",
      name: "localDataStillLockedTitle",
      desc:
          "Title of the start-up screen shown when the keyring stayed locked for two minutes",
    );

String get localDataStillLockedBody => Intl.message(
      "Vommet needs your system keyring unlocked to open your messages on this device. Nothing was changed or lost.",
      name: "localDataStillLockedBody",
      desc:
          "Body of the start-up screen shown when the keyring stayed locked for two minutes",
    );

String get localDataTryAgain => Intl.message(
      "Try again",
      name: "localDataTryAgain",
      desc: "Button trying again to open the encrypted data",
    );

// Start-up: the key is missing or can't be reached.

String get localDataMissingTitle => Intl.message(
      "Vommet can't find the key to your messages on this device",
      name: "localDataMissingTitle",
      desc:
          "Title of the start-up screen shown when the encryption key isn't where it was kept",
    );

String get localDataMissingKeyringBody => Intl.message(
      "Your messages and settings on this device are encrypted, and the key was kept in your system keyring. The keyring is open, but the key isn't in it anymore. This can happen if the keyring was reset or you switched to another desktop.",
      name: "localDataMissingKeyringBody",
      desc:
          "Body of the start-up screen shown when the keyring no longer has the encryption key",
    );

String get localDataMissingFileBody => Intl.message(
      "Your messages and settings on this device are encrypted, and the key was kept in a file in Vommet's folder. That file is gone or doesn't hold the key anymore.",
      name: "localDataMissingFileBody",
      desc:
          "Body of the start-up screen shown when the key file no longer has the encryption key",
    );

String get localDataMissingRecordBody => Intl.message(
      "Your messages and settings on this device are encrypted, but the list of their keys in Vommet's folder is missing or damaged.",
      name: "localDataMissingRecordBody",
      desc:
          "Body of the start-up screen shown when the app's record of its encryption keys (a file) is missing or damaged",
    );

String get localDataNothingDeleted => Intl.message(
      "Nothing has been deleted.",
      name: "localDataNothingDeleted",
      desc: "Reassurance on the start-up screens about the encryption key",
    );

String get localDataNeverNewKey => Intl.message(
      "Vommet never makes a new key over your data. If you can get the old keyring back, do that and select Try again.",
      name: "localDataNeverNewKey",
      desc: "Advice on the start-up screen shown when the key is missing",
    );

String localDataDetailWhere(String place) => Intl.message(
      "Where the key was kept: $place",
      name: "localDataDetailWhere",
      args: [place],
      desc:
          "Details line on the key start-up screens. place is like System keyring or A file on this device",
    );

String localDataDetailWhat(String what) => Intl.message(
      "What happened: $what",
      name: "localDataDetailWhat",
      args: [what],
      desc: "Details line on the key start-up screens",
    );

String get localDataWhatNoKey => Intl.message(
      "the keyring answered, but has no Vommet key",
      name: "localDataWhatNoKey",
      desc: "What happened, on the start-up screen when the key is missing",
    );

String get localDataWhatFileGone => Intl.message(
      "the key file is gone or holds another key",
      name: "localDataWhatFileGone",
      desc:
          "What happened, on the start-up screen when the key file is missing",
    );

String get localDataWhatRecordGone => Intl.message(
      "the list of keys (keystore.json) is missing or damaged",
      name: "localDataWhatRecordGone",
      desc:
          "What happened, on the start-up screen when the app's list of keys is missing. keystore.json is a file name and stays as it is",
    );

String get localDataWhatUnreachable => Intl.message(
      "the keyring doesn't answer",
      name: "localDataWhatUnreachable",
      desc:
          "What happened, on the start-up screen when the keyring can't be reached",
    );

String get localDataWhatDamaged => Intl.message(
      "the file doesn't open with its key (checked 3 times)",
      name: "localDataWhatDamaged",
      desc:
          "What happened, on the start-up screen when an account's database is damaged",
    );

String get localDataWhatNoFileKey => Intl.message(
      "Vommet has no key for this file",
      name: "localDataWhatNoFileKey",
      desc:
          "What happened, on the start-up screen when an encrypted database has no key recorded",
    );

String localDataDetailFolder(String path) => Intl.message(
      "Data folder: $path",
      name: "localDataDetailFolder",
      args: [path],
      desc: "Details line on the key start-up screens. path is a folder",
    );

String get localDataCopyDetails => Intl.message(
      "Copy details",
      name: "localDataCopyDetails",
      desc: "Button copying the details of a start-up problem",
    );

String get localDataDetails => Intl.message(
      "Details",
      name: "localDataDetails",
      desc: "Button showing the details of a start-up problem",
    );

String get localDataHideDetails => Intl.message(
      "Hide details",
      name: "localDataHideDetails",
      desc: "Button hiding the details of a start-up problem",
    );

String get localDataStartOverButton => Intl.message(
      "Start over on this device…",
      name: "localDataStartOverButton",
      desc:
          "Button on the key start-up screens; opens a dialog to remove the app's data on the device and start fresh",
    );

String get localDataUnreachableTitle => Intl.message(
      "Vommet can't reach the key to your messages",
      name: "localDataUnreachableTitle",
      desc:
          "Title of the start-up screen shown when the keyring holding the key doesn't answer",
    );

String get localDataUnreachableBody => Intl.message(
      "The key to your messages on this device is kept in your system keyring, but Vommet can't reach the keyring right now. If you just switched desktops, or the keyring app isn't running, start it and try again.",
      name: "localDataUnreachableBody",
      desc:
          "Body of the start-up screen shown when the keyring holding the key doesn't answer",
    );

// Start over.

String get localDataStartOverTitle => Intl.message(
      "Start over on this device?",
      name: "localDataStartOverTitle",
      desc: "Title of the dialog removing the app's data on the device",
    );

String get localDataStartOverBody => Intl.message(
      "Without the key, Vommet can't open anything it stored on this device. Starting over removes it, and you sign in to your accounts again. Your chats and messages come back from your server, and your settings go back to their defaults.",
      name: "localDataStartOverBody",
      desc: "Body of the dialog removing the app's data on the device",
    );

String get localDataRecoveryKeyLine => Intl.message(
      "To read older encrypted messages again, you'll need your recovery key, or another signed-in device to verify with.",
      name: "localDataRecoveryKeyLine",
      desc:
          "Line in the dialogs removing data from the device, about reading end-to-end encrypted history",
    );

String get localDataKeepCopy => Intl.message(
      "Keep a copy of the old files",
      name: "localDataKeepCopy",
      desc: "Checkbox in the dialogs removing data from the device",
    );

String localDataKeepCopyDescription(String folder) => Intl.message(
      "Moved to a folder named “$folder” in case the key turns up. Delete it yourself when you're sure.",
      name: "localDataKeepCopyDescription",
      args: [folder],
      desc:
          "Description of the Keep a copy checkbox. folder is a folder name like vommet-old-2026-10-27",
    );

String get localDataCancel => Intl.message(
      "Cancel",
      name: "localDataCancel",
      desc: "Button closing a dialog without doing anything",
    );

String get localDataStartOver => Intl.message(
      "Start over",
      name: "localDataStartOver",
      desc: "Button removing the app's data on the device (critical action)",
    );

// Damaged database.

String get localDataDamagedTitle => Intl.message(
      "Some of your data on this device can't be opened",
      name: "localDataDamagedTitle",
      desc:
          "Title of the start-up screen shown when an account's stored messages are damaged",
    );

String localDataDamagedBody(String account) => Intl.message(
      "The stored messages for $account seem to be damaged, maybe after a crash, a full disk or a disk error. The key is fine, and your other accounts aren't affected.",
      name: "localDataDamagedBody",
      args: [account],
      desc:
          "Body of the start-up screen shown when an account's stored messages are damaged. account is like Alex (@alex:example.org), or this account",
    );

String get localDataDamagedSafe => Intl.message(
      "Your messages are safe on your server. Resetting this account's data signs you in again and downloads them fresh.",
      name: "localDataDamagedSafe",
      desc:
          "Line on the start-up screen shown when an account's stored messages are damaged",
    );

String get localDataThisAccount => Intl.message(
      "this account",
      name: "localDataThisAccount",
      desc:
          "Stands for an account whose name isn't known, in sentences like Reset this account's data",
    );

String localDataDetailAccount(String id) => Intl.message(
      "Account: $id",
      name: "localDataDetailAccount",
      args: [id],
      desc:
          "Details line on the damaged data screen. id is like @alex:example.org",
    );

String localDataDetailFile(String path, String size) => Intl.message(
      "File: $path ($size)",
      name: "localDataDetailFile",
      args: [path, size],
      desc:
          "Details line on the damaged data screen. path is a file, size like 412 MB",
    );

String localDataContinueWithout(String name) => Intl.message(
      "Continue without $name for now",
      name: "localDataContinueWithout",
      args: [name],
      desc:
          "Button on the damaged data screen: start the app without this account (it asks again at the next start). name is the account's name",
    );

String localDataResetAccountButton(String name) => Intl.message(
      "Reset $name's data…",
      name: "localDataResetAccountButton",
      args: [name],
      desc:
          "Button on the damaged data screen opening the reset dialog. name is the account's name",
    );

String localDataResetTitle(String name) => Intl.message(
      "Reset $name's data on this device?",
      name: "localDataResetTitle",
      args: [name],
      desc: "Title of the dialog resetting an account's data on the device",
    );

String localDataResetBody(String name) => Intl.message(
      "Vommet removes what it stored on this device for $name and you sign in again. Your chats and messages come back from your server.",
      name: "localDataResetBody",
      args: [name],
      desc: "Body of the dialog resetting an account's data on the device",
    );

String get localDataResetConfirm => Intl.message(
      "Reset and sign in again",
      name: "localDataResetConfirm",
      desc: "Button resetting an account's data on the device",
    );

// Settings › Privacy › Data on this device.

String get localDataSettingsTitle => Intl.message(
      "Data on this device",
      name: "localDataSettingsTitle",
      desc:
          "Title of the settings section about encrypting the data the app stores on the device",
    );

String get localDataSwitch => Intl.message(
      "Encrypt data on this device",
      name: "localDataSwitch",
      desc: "Switch turning on encryption of the data stored on the device",
    );

String get localDataOffDescription => Intl.message(
      "Your messages on this device aren't encrypted. Media is always encrypted.",
      name: "localDataOffDescription",
      desc: "Settings: shown while encryption of the data on the device is off",
    );

String get localDataEncrypted => Intl.message(
      "Encrypted",
      name: "localDataEncrypted",
      desc: "Settings: status of data on the device that is encrypted",
    );

String get localDataEncryptedDescription => Intl.message(
      "Everything Vommet keeps on this device is encrypted: your messages, search index, media and settings.",
      name: "localDataEncryptedDescription",
      desc: "Settings: shown when everything on the device is encrypted",
    );

String get localDataNotEncryptedYet => Intl.message(
      "Not encrypted yet",
      name: "localDataNotEncryptedYet",
      desc: "Settings: status of data on the device not encrypted yet",
    );

String get localDataNotDecryptedYet => Intl.message(
      "Not decrypted yet",
      name: "localDataNotDecryptedYet",
      desc:
          "Settings: status of data on the device still encrypted after encryption was turned off",
    );

String get localDataDecrypted => Intl.message(
      "Not encrypted",
      name: "localDataDecrypted",
      desc: "Settings: status of data on the device that isn't encrypted",
    );

String localDataRowMessages(String name) => Intl.message(
      "$name · messages and search",
      name: "localDataRowMessages",
      args: [name],
      desc:
          "Settings: row naming an account's stored messages and search index",
    );

String get localDataRowMedia => Intl.message(
      "Media and app data",
      name: "localDataRowMedia",
      desc: "Settings: row naming the media cache and the app's own data",
    );

String get localDataPendingEncrypt => Intl.message(
      "Vommet encrypts your data the next time it starts.",
      name: "localDataPendingEncrypt",
      desc:
          "Settings: shown after encryption was turned on, until the app restarts",
    );

String get localDataPendingDecrypt => Intl.message(
      "Vommet decrypts your data the next time it starts.",
      name: "localDataPendingDecrypt",
      desc:
          "Settings: shown after encryption was turned off, until the app restarts",
    );

String get localDataWhereKept => Intl.message(
      "Where the key is kept",
      name: "localDataWhereKept",
      desc:
          "Settings: heading of the choice of where the encryption key is kept",
    );

String localDataRightNow(String place) => Intl.message(
      "Right now: $place",
      name: "localDataRightNow",
      args: [place],
      desc:
          "Settings: where the encryption key is kept now. place is like System keyring",
    );

String get localDataPlaceKeyring => Intl.message(
      "System keyring",
      name: "localDataPlaceKeyring",
      desc: "Where the encryption key is kept: the desktop's keyring",
    );

String get localDataPlaceFile => Intl.message(
      "A file on this device",
      name: "localDataPlaceFile",
      desc: "Where the encryption key is kept: a file in the app's folder",
    );

String get localDataPlaceWindows => Intl.message(
      "Your Windows account",
      name: "localDataPlaceWindows",
      desc: "Where the encryption key is kept: protected by Windows",
    );

String get localDataPlaceAndroid => Intl.message(
      "Android's secure key storage",
      name: "localDataPlaceAndroid",
      desc: "Where the encryption key is kept on Android",
    );

String get localDataPlaceDevice => Intl.message(
      "This device's secure key storage",
      name: "localDataPlaceDevice",
      desc: "Where the encryption key is kept on iPhone and iPad",
    );

String get localDataPlaceMac => Intl.message(
      "Mac Keychain",
      name: "localDataPlaceMac",
      desc: "Where the encryption key is kept: the Mac's Keychain",
    );

String get localDataRecommended => Intl.message(
      "Recommended",
      name: "localDataRecommended",
      desc: "Tag on the recommended place to keep the encryption key",
    );

String get localDataKeyringDescription => Intl.message(
      "It's locked when you're signed out, and only you can open it.",
      name: "localDataKeyringDescription",
      desc: "Settings: description of keeping the key in the system keyring",
    );

String get localDataNoKeyringFound => Intl.message(
      "No system keyring or password manager was found on this computer.",
      name: "localDataNoKeyringFound",
      desc: "Settings: the system keyring choice when none was found",
    );

String get localDataFileDescription => Intl.message(
      "Kept in Vommet's folder. Works everywhere, but anyone who can open your files can open the key too.",
      name: "localDataFileDescription",
      desc: "Settings: description of keeping the key in a file",
    );

String get localDataWindowsDescription => Intl.message(
      "Protected by Windows so only you, signed in to this computer, can open it.",
      name: "localDataWindowsDescription",
      desc: "Settings: description of keeping the key with the Windows account",
    );

String get localDataMacUnavailable => Intl.message(
      "Available once Vommet's Mac app is signed. Until then, the Keychain would ask for permission after every update.",
      name: "localDataMacUnavailable",
      desc: "Settings: why the Mac Keychain can't be chosen yet",
    );

String get localDataAndroidDescription => Intl.message(
      "On Android the key is always kept in the phone's own secure storage, so there's nothing to choose here. Vommet's data isn't included in Android backups.",
      name: "localDataAndroidDescription",
      desc: "Settings: where the key is kept on Android",
    );

String get localDataIosDescription => Intl.message(
      "On this device the key is always kept in its own secure storage, so there's nothing to choose here.",
      name: "localDataIosDescription",
      desc: "Settings: where the key is kept on iPhone and iPad",
    );

String get localDataAutoMove => Intl.message(
      "Move it into a keyring when one is available",
      name: "localDataAutoMove",
      desc:
          "Settings switch: move the key from the file into a keyring automatically",
    );

String get localDataAutoMoveDescription => Intl.message(
      "Vommet checks each time it starts. Turn off to keep the key in the file.",
      name: "localDataAutoMoveDescription",
      desc: "Settings: description of the automatic move switch",
    );

String get localDataFooter => Intl.message(
      "Copies from before encryption may remain in old backups, or on the disk until it's reused. For the best protection, also turn on full-disk encryption.",
      name: "localDataFooter",
      desc: "Settings: note under the encryption settings",
    );

String localDataNoSpaceEncrypt(String size, String name) => Intl.message(
      "Free up $size on this device to finish encrypting $name's messages. Vommet keeps working in the meantime and tries again the next time it starts.",
      name: "localDataNoSpaceEncrypt",
      args: [size, name],
      desc:
          "Shown when there isn't enough free space to encrypt an account's messages. size is like 120 MB, name the account's name",
    );

String localDataNoSpaceDecrypt(String size, String name) => Intl.message(
      "Free up $size on this device to finish decrypting $name's messages. Vommet keeps working in the meantime and tries again the next time it starts.",
      name: "localDataNoSpaceDecrypt",
      args: [size, name],
      desc:
          "Shown when there isn't enough free space to decrypt an account's messages. size is like 120 MB, name the account's name",
    );

String localDataFailedTitle(String name) => Intl.message(
      "$name's messages aren't encrypted yet",
      name: "localDataFailedTitle",
      args: [name],
      desc:
          "Settings: encrypting an account's messages failed several times. name is the account's name",
    );

String get localDataFailedBody => Intl.message(
      "Encrypting them failed several times, so they stay unencrypted for now.",
      name: "localDataFailedBody",
      desc: "Settings: encrypting an account's messages failed several times",
    );

String localDataDecryptFailedTitle(String name) => Intl.message(
      "$name's messages aren't decrypted yet",
      name: "localDataDecryptFailedTitle",
      args: [name],
      desc:
          "Settings: decrypting an account's messages failed several times. name is the account's name",
    );

String get localDataDecryptFailedBody => Intl.message(
      "Decrypting them failed several times, so they stay encrypted for now.",
      name: "localDataDecryptFailedBody",
      desc: "Settings: decrypting an account's messages failed several times",
    );

String get localDataTryAgainNextStart => Intl.message(
      "Try again next start",
      name: "localDataTryAgainNextStart",
      desc: "Settings button: try again the next time the app starts",
    );

String get localDataMoveToFileTitle => Intl.message(
      "Keep the key in a file instead?",
      name: "localDataMoveToFileTitle",
      desc: "Title of the dialog moving the key out of the keyring into a file",
    );

String get localDataMoveToFileBody => Intl.message(
      "The key that opens your messages on this device will move out of your system keyring into a file in Vommet's folder. Anyone who can open your files will be able to open the key too.",
      name: "localDataMoveToFileBody",
      desc: "Body of the dialog moving the key into a file",
    );

String get localDataMoveToFileNoMoveBack => Intl.message(
      "Vommet won't move it back on its own. You can change this here anytime.",
      name: "localDataMoveToFileNoMoveBack",
      desc: "Second line of the dialog moving the key into a file",
    );

String get localDataMoveToFileConfirm => Intl.message(
      "Move to a file",
      name: "localDataMoveToFileConfirm",
      desc: "Button moving the key into a file",
    );

String get localDataMoveFailedTitle => Intl.message(
      "Couldn't move the key",
      name: "localDataMoveFailedTitle",
      desc: "Title of the dialog shown when moving the key failed",
    );

String get localDataMoveFailedBody => Intl.message(
      "Your system keyring is locked. Unlock it and try again. The key stays where it was, and nothing else changed.",
      name: "localDataMoveFailedBody",
      desc:
          "Body of the dialog shown when moving the key into the keyring failed",
    );

String get localDataConfirmOnTitle => Intl.message(
      "Encrypt your data on this device?",
      name: "localDataConfirmOnTitle",
      desc: "Title of the dialog confirming turning on encryption",
    );

String get localDataConfirmOnBody => Intl.message(
      "Vommet encrypts it the next time it starts. This takes a few minutes.",
      name: "localDataConfirmOnBody",
      desc: "Body of the dialog confirming turning on encryption",
    );

String get localDataRestartNow => Intl.message(
      "Restart now",
      name: "localDataRestartNow",
      desc:
          "Button closing the app so the change happens when it is opened again",
    );

String get localDataCloseApp => Intl.message(
      "Close Vommet",
      name: "localDataCloseApp",
      desc:
          "Button closing the app so the change happens when it is opened again, where the app can't restart itself",
    );

String get localDataEncryptNextStart => Intl.message(
      "Encrypt at next start",
      name: "localDataEncryptNextStart",
      desc: "Button turning on encryption from the next start",
    );

String get localDataConfirmOffTitle => Intl.message(
      "Stop encrypting data on this device?",
      name: "localDataConfirmOffTitle",
      desc: "Title of the dialog confirming turning off encryption",
    );

String get localDataConfirmOffBody => Intl.message(
      "Vommet decrypts it the next time it starts. The keys for your stored messages are then removed. Media stays encrypted.",
      name: "localDataConfirmOffBody",
      desc: "Body of the dialog confirming turning off encryption",
    );

String get localDataSettingSaveFailedTitle => Intl.message(
      "Couldn't save the setting",
      name: "localDataSettingSaveFailedTitle",
      desc:
          "Title of the dialog shown when turning encryption on or off couldn't be saved",
    );

String get localDataSettingSaveFailedBody => Intl.message(
      "Nothing changed. Check that your disk isn't full, then try again.",
      name: "localDataSettingSaveFailedBody",
      desc:
          "Body of the dialog shown when turning encryption on or off couldn't be saved",
    );

String get localDataDecryptNextStart => Intl.message(
      "Decrypt at next start",
      name: "localDataDecryptNextStart",
      desc: "Button turning off encryption from the next start",
    );

String get localDataSearchKeywords => Intl.message(
      "encryption, key, keyring, password manager",
      name: "localDataSearchKeywords",
      desc:
          "Comma-separated words that find the Data on this device settings in the settings search",
    );

// Splash and notices.

String localDataEncryptingProgress(int percent) => Intl.message(
      "Encrypting your messages on this device… $percent%",
      name: "localDataEncryptingProgress",
      args: [percent],
      desc: "Splash screen while the app encrypts its data. percent is 0-100",
    );

String localDataDecryptingProgress(int percent) => Intl.message(
      "Decrypting your messages on this device… $percent%",
      name: "localDataDecryptingProgress",
      args: [percent],
      desc: "Splash screen while the app decrypts its data. percent is 0-100",
    );

String localDataSplashStep(int index, int count) => Intl.message(
      "Step $index of $count. This happens once and can take a few minutes.",
      name: "localDataSplashStep",
      args: [index, count],
      desc: "Splash screen while the app encrypts or decrypts its data",
    );

String get localDataSplashKeepOpen => Intl.message(
      "Keep Vommet open until it's done.",
      name: "localDataSplashKeepOpen",
      desc: "Splash screen while the app encrypts or decrypts its data",
    );

String get localDataNoSpaceTitle => Intl.message(
      "Not enough space to encrypt your local data",
      name: "localDataNoSpaceTitle",
      desc:
          "Title of a notice shown when there isn't enough free disk space to encrypt the app's databases on the device",
    );

String get localDataNoSpaceDecryptTitle => Intl.message(
      "Not enough space to decrypt your local data",
      name: "localDataNoSpaceDecryptTitle",
      desc:
          "Title of a notice shown when there isn't enough free disk space to decrypt the app's databases on the device",
    );
