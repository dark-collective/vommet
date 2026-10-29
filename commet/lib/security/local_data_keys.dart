// Vommet: local data encryption, the app-facing entry points of the key
// vault. Native platforms keep the media cache encrypted with a key derived
// from a master key in the platform's key store, and the local databases
// too when the user turned that on (opt-in, LocalDataSetting); the web
// build has no vault (its databases live in the browser's storage).
import 'package:commet/security/local_data_keys_stub.dart'
    if (dart.library.io) 'package:commet/security/local_data_keys_io.dart'
    as impl;

/// What the start-up migration left to do, for the notices shown once the
/// app is in.
class LocalDataMigrationSummary {
  const LocalDataMigrationSummary(
      {this.bytesToFree,
      this.noSpaceAccount,
      this.stoppedRetrying = false,
      this.decrypting = false});

  /// Free space still needed to convert the biggest file left, or null.
  final int? bytesToFree;

  /// The account whose file needs [bytesToFree] (null: the app's own).
  final String? noSpaceAccount;

  /// A message store failed too often and isn't retried on its own any
  /// more (shown in the settings, with Try again next start).
  final bool stoppedRetrying;

  /// The run decrypted (encryption was turned off).
  final bool decrypting;
}

typedef MigrationProgressCallback = void Function(
    int index, int count, double fraction);

/// Where the master key is kept, in the words of the settings.
enum LocalDataKeyPlace { keyring, portal, windows, android, ios, mac, file }

enum LocalDataStartupScreen { locked, missing, unreachable }

enum LocalDataMissingCause { keyringEmpty, fileGone, recordGone }

/// Why the app can't open its encrypted data at start-up.
class LocalDataStartupProblem {
  const LocalDataStartupProblem(this.screen,
      {this.place, this.cause, required this.dataFolder});

  final LocalDataStartupScreen screen;
  final LocalDataKeyPlace? place;
  final LocalDataMissingCause? cause;

  /// The app's data folder, for Details (home shortened to ~).
  final String dataFolder;
}

/// An account whose encrypted message store doesn't open with its key.
class LocalDataDamagedAccount {
  const LocalDataDamagedAccount(
      {required this.account,
      required this.filePath,
      this.size,
      this.displayName,
      this.userId,
      this.noKey = false,
      this.corrupt = false});

  /// The client name (registered matrix client).
  final String account;
  final String filePath;
  final int? size;

  /// Remembered from the last run (only while encryption is on).
  final String? displayName;
  final String? userId;

  /// There is no key for it at all (not a damaged file).
  final bool noKey;

  /// The file is damaged or its key is wrong (SQLite NOTADB / CORRUPT),
  /// not a failure that may pass (busy, I/O, out of memory): only then is
  /// Reset offered.
  final bool corrupt;
}

class LocalDataAccountRow {
  const LocalDataAccountRow(this.account, {required this.encrypted});
  final String account;
  final bool encrypted;
}

/// What Settings › Privacy › Data on this device shows.
class LocalDataPanelStatus {
  const LocalDataPanelStatus({
    required this.encrypt,
    required this.vaultReady,
    required this.accounts,
    required this.appDataEncrypted,
    this.place,
    this.pinnedToFile = false,
    this.keyringAvailable = false,
    this.keyringChoosable = false,
    this.bytesToFree,
    this.noSpaceAccount,
    this.failedAccount,
  });

  /// The setting (what the next start does).
  final bool encrypt;
  final bool vaultReady;
  final List<LocalDataAccountRow> accounts;
  final bool appDataEncrypted;

  final LocalDataKeyPlace? place;
  final bool pinnedToFile;

  /// A system keyring answered (locked or not).
  final bool keyringAvailable;

  /// This platform has a keyring to choose (not Android/iOS, not unsigned
  /// macOS).
  final bool keyringChoosable;

  final int? bytesToFree;
  final String? noSpaceAccount;

  /// An account that stopped being retried (failed too often).
  final String? failedAccount;

  bool get allEncrypted =>
      appDataEncrypted && accounts.every((a) => a.encrypted);
  bool get allPlain => !appDataEncrypted && accounts.every((a) => !a.encrypted);
}

class LocalDataKeys {
  /// Reads the setting and loads (or, in the UI engine, creates) the master
  /// key. Never throws: a vault that isn't ready only fails the encrypted
  /// databases, which report it when they are opened. With [deferPrompt]
  /// a locked keyring isn't asked to unlock here: the start-up screen does
  /// it ([startupProblem], [retryUnlock]).
  static Future<void> init(
          {required bool headless, bool deferPrompt = false}) =>
      impl.initLocalDataKeys(headless: headless, deferPrompt: deferPrompt);

  /// The engine became the app's UI engine.
  static Future<void> becomeUiEngine() => impl.becomeUiEngine();

  /// Whether the databases are (to be) encrypted: the user's setting.
  static bool get encrypt => impl.settingEncrypt();

  /// Whether the user answered (first-run page, notice or settings).
  static bool get chosen => impl.settingChosen();

  /// Whether this build keeps local data encrypted at all (not on web).
  static bool get supported => impl.supported;

  /// Turns database encryption on or off from the next start ([source]:
  /// first_run, settings or notice, for telemetry). Never throws. False
  /// when the setting couldn't be saved (nothing changes; see
  /// [settingWriteError]).
  static Future<bool> choose(bool encrypt, {required String source}) =>
      impl.choose(encrypt, source: source);

  /// Why the last [choose] couldn't save the setting, or null.
  static String? get settingWriteError => impl.settingWriteError();

  /// Encrypts the local databases that are still plaintext, or decrypts
  /// them when encryption was turned off (a no-op when there is nothing to
  /// do). Call in the UI engine after [init] and before the database
  /// server opens anything. [onProgress] is only called when there is work
  /// to do. Throws only when the app must not start (a converted copy
  /// couldn't be put in place; the next start finishes it).
  static Future<void> migrate(
      {MigrationProgressCallback? onProgress, bool retryFailed = false}) async {
    lastMigration = await impl.migrateLocalData(
        onProgress: onProgress, retryFailed: retryFailed);
  }

  /// Whether [migrate] decrypts (for the splash).
  static bool get decrypting => !encrypt;

  /// What the last [migrate] left to do; null when it finished or didn't
  /// run.
  static LocalDataMigrationSummary? lastMigration;

  /// Why the encrypted data can't be opened, or null (also null while
  /// encryption is off and nothing is encrypted: then a locked keyring only
  /// turns the media cache's encryption off for the run).
  static Future<LocalDataStartupProblem?> startupProblem() =>
      impl.startupProblem();

  /// Asks the key store again (unlocking a locked keyring may show the
  /// system's prompt and wait up to two minutes).
  static Future<LocalDataStartupProblem?> retryUnlock() => impl.retryUnlock();

  /// Encrypted message stores that don't open with their key (each tried 3
  /// times). A damaged encrypted search index is deleted (it is rebuilt)
  /// and a damaged app_data.db is set aside, silently.
  static Future<List<LocalDataDamagedAccount>> checkDatabases({String? only}) =>
      impl.checkDatabases(only: only);

  /// The accounts signed in on this device (client names).
  static List<String> get registeredAccounts => impl.registeredAccounts();

  /// Accounts left out of this run (Continue without).
  static final Set<String> skippedAccounts = {};

  /// Removes everything the app stored on this device (Start over): moved
  /// into a folder named [oldFolderName] next to it with [keepCopy], else
  /// deleted. The accounts are signed out here; the encryption setting is
  /// kept.
  static Future<void> startOver({required bool keepCopy}) =>
      impl.startOver(keepCopy: keepCopy);

  /// Removes one account's stored messages and search index here (Reset)
  /// and signs it out here.
  static Future<void> resetAccount(String account, {required bool keepCopy}) =>
      impl.resetAccount(account, keepCopy: keepCopy);

  /// "vommet-old-YYYY-MM-DD" for today.
  static String oldFolderName([DateTime? now]) {
    final d = now ?? DateTime.now();
    String two(int n) => n.toString().padLeft(2, "0");
    return "vommet-old-${d.year}-${two(d.month)}-${two(d.day)}";
  }

  /// Remembers the accounts' names for the damaged-data screen (only while
  /// encryption is on; forgotten when it is off).
  static Future<void> rememberAccountLabels(
          Map<String, ({String? name, String? userId})> labels) =>
      impl.rememberAccountLabels(labels);

  static Future<LocalDataPanelStatus?> panelStatus() => impl.panelStatus();

  /// Moves the key ([LocalDataKeyPlace.file] with [pin]: the user chose the
  /// file, no automatic move back). False when the target couldn't keep it
  /// (it stays where it was).
  static Future<bool> moveKey(LocalDataKeyPlace target, {bool pin = false}) =>
      impl.moveKey(target, pin: pin);

  /// Whether the "your key is kept in a file" notice is due (only while
  /// encryption is on).
  static bool get keyFileNoticeDue => impl.keyFileNoticeDue();

  static Future<void> acknowledgeKeyFileNotice() =>
      impl.acknowledgeKeyFileNotice();

  /// The account was signed out here: its database keys are forgotten
  /// (best effort: what is left of its databases can't be decrypted from
  /// this device's current keystore.json; see forget_account.dart) and its database
  /// files deleted. Never throws.
  static Future<void> forgetAccount(String account) =>
      impl.forgetAccount(account);

  /// "Try again next start": a message store that stopped being retried is
  /// tried again on the next start.
  static Future<void> retryMigrationNextStart() =>
      impl.resetMigrationFailures();
}
