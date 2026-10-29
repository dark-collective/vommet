// Vommet: the web build keeps no local data key (see local_data_keys.dart).
import 'package:commet/security/local_data_keys.dart';

const bool supported = false;

Future<void> initLocalDataKeys(
    {required bool headless, bool deferPrompt = false}) async {}

Future<void> becomeUiEngine() async {}

bool settingEncrypt() => false;

bool settingChosen() => true;

List<String> registeredAccounts() => const [];

Future<bool> choose(bool encrypt, {required String source}) async => true;

String? settingWriteError() => null;

Future<LocalDataMigrationSummary?> migrateLocalData(
        {MigrationProgressCallback? onProgress,
        bool retryFailed = false}) async =>
    null;

Future<LocalDataStartupProblem?> startupProblem() async => null;

Future<LocalDataStartupProblem?> retryUnlock() async => null;

Future<List<LocalDataDamagedAccount>> checkDatabases({String? only}) async =>
    const [];

Future<void> startOver({required bool keepCopy}) async {}

Future<void> resetAccount(String account, {required bool keepCopy}) async {}

Future<void> rememberAccountLabels(
    Map<String, ({String? name, String? userId})> labels) async {}

Future<LocalDataPanelStatus?> panelStatus() async => null;

Future<bool> moveKey(LocalDataKeyPlace target, {bool pin = false}) async =>
    false;

bool keyFileNoticeDue() => false;

Future<void> acknowledgeKeyFileNotice() async {}

Future<void> resetMigrationFailures() async {}

Future<void> forgetAccount(String account) async {}
