import 'package:intl/intl.dart';

/// Translatable labels and fixed reasons; no SDK payloads or error strings.
abstract final class DiagnosticStrings {
  static String get title =>
      Intl.message('Notification troubleshooter', name: 'notifyDiagTitle');
  static String get entry => Intl.message(
      'Check permissions, Android categories, push provider and server registration. No notifications are sent.',
      name: 'notifyDiagEntry');
  static String get lead => Intl.message(
      'Check this device and the selected account. Checks do not change settings or send notifications.',
      name: 'notifyDiagLead');
  static String get account =>
      Intl.message('Account to check', name: 'notifyDiagAccount');
  static String get configuration =>
      Intl.message('Configuration', name: 'notifyDiagConfiguration');
  static String get delivery =>
      Intl.message('Delivery is unverified', name: 'notifyDiagDelivery');
  static String get local =>
      Intl.message('Local presentation', name: 'notifyDiagLocal');
  static String get remote =>
      Intl.message('Server-to-device test', name: 'notifyDiagRemote');
  static String get localLimit => Intl.message(
      'Not tested here. A local notification would only test this device, not remote delivery.',
      name: 'notifyDiagLocalLimit');
  static String get remoteLimit => Intl.message(
      'This version has no supported homeserver delivery test. Configuration checks cannot prove that pushes arrive.',
      name: 'notifyDiagRemoteLimit');
  static String get limits => Intl.message(
      'Results describe this check only. Sound and pop-up behavior can also depend on Do Not Disturb, battery restrictions, category groups and device settings. Checks do not open your distributor or repair push registrations.',
      name: 'notifyDiagLimits');
  static String get cancel =>
      Intl.message('Cancel checks', name: 'notifyDiagCancel');
  static String get again =>
      Intl.message('Check again', name: 'notifyDiagAgain');
  static String get settings =>
      Intl.message('Notification settings', name: 'notifyDiagSettings');
  static String get androidSettings => Intl.message('Open Android app settings',
      name: 'notifyDiagAndroidSettings');
  static String get providerSettings =>
      Intl.message('Provider and notification settings',
          name: 'notifyDiagProviderSettings');
  static String get notifications =>
      Intl.message('Notifications', name: 'notifyDiagNotifications');
  static String get openFailed => Intl.message(
      'Settings could not be opened. Open your device’s app settings manually, then check again.',
      name: 'notifyDiagOpenFailed');
  static String get notChecked =>
      Intl.message('Not checked', name: 'notifyDiagNotChecked');
  static String get checking =>
      Intl.message('Checking', name: 'notifyDiagChecking');
  static String get passed => Intl.message('Passed', name: 'notifyDiagPassed');
  static String get failed => Intl.message('Failed', name: 'notifyDiagFailed');
  static String get attention =>
      Intl.message('Needs attention', name: 'notifyDiagAttention');
  static String get unknown =>
      Intl.message('Unknown', name: 'notifyDiagUnknown');
  static String get unavailable =>
      Intl.message('Not available', name: 'notifyDiagUnavailable');
  static String get waiting =>
      Intl.message('Waiting to check.', name: 'notifyDiagWaiting');
  static String get reading =>
      Intl.message('Reading current configuration…', name: 'notifyDiagReading');
  static String get setupError => Intl.message(
      'Configuration could not be read. Check again after app setup.',
      name: 'notifyDiagSetupError');
  static String get timeout => Intl.message(
      'The check timed out. No result was confirmed. Check your connection and try again.',
      name: 'notifyDiagTimeout');
  static String get readError => Intl.message(
      'Could not read this setting. Check your connection and sign-in, then try again.',
      name: 'notifyDiagReadError');
  static String get canceled => Intl.message(
      'Checks canceled. Check again for current results. No settings were changed.',
      name: 'notifyDiagCanceled');
  static String get changed => Intl.message(
      'Configuration changed or settings were opened. Check again for current results.',
      name: 'notifyDiagChanged');
  static String get permission =>
      Intl.message('System permission', name: 'notifyDiagPermission');
  static String get channels =>
      Intl.message('Notification channels', name: 'notifyDiagChannels');
  static String get provider =>
      Intl.message('Notification provider', name: 'notifyDiagProvider');
  static String get registration =>
      Intl.message('Server registration', name: 'notifyDiagRegistration');
  static String get messages =>
      Intl.message('Messages', name: 'notifyDiagMessages');
  static String get messagesMentions =>
      Intl.message('Messages and mentions', name: 'notifyDiagMessagesMentions');
  static String get mentions =>
      Intl.message('Mentions and replies', name: 'notifyDiagMentions');
  static String get invites =>
      Intl.message('Chat invitations', name: 'notifyDiagInvites');
  static String get calls =>
      Intl.message('Incoming calls', name: 'notifyDiagCalls');
  static String get permissionUnknown => Intl.message(
      'System notification permission cannot be confirmed here. Review your system settings.',
      name: 'notifyDiagPermissionUnknown');
  static String get androidAllowed => Intl.message(
      'Android allows Vommet notifications. Channels and device settings may still suppress alerts.',
      name: 'notifyDiagAndroidAllowed');
  static String get androidBlocked => Intl.message(
      'Android blocks Vommet notifications. Open app settings, then choose Notifications.',
      name: 'notifyDiagAndroidBlocked');
  static String get channelsUnavailable => Intl.message(
      'Android notification categories do not apply to this platform.',
      name: 'notifyDiagChannelsUnavailable');
  static String get channelMissing => Intl.message(
      'Category is not available or has not been created yet. No notification was sent to create it.',
      name: 'notifyDiagChannelMissing');
  static String get channelBlocked => Intl.message(
      'This category is blocked. Open app settings, then choose Notifications.',
      name: 'notifyDiagChannelBlocked');
  static String get channelUnknown => Intl.message(
      'The system did not report category importance or category-group blocking could not be checked.',
      name: 'notifyDiagChannelUnknown');
  static String get channelQuiet => Intl.message(
      'Sound is off or importance is below high. Sound or pop-up alerts may be suppressed.',
      name: 'notifyDiagChannelQuiet');
  static String get channelAllowed => Intl.message(
      'Sound is configured and importance is high. Device settings can still suppress alerts.',
      name: 'notifyDiagChannelAllowed');
  static String get providerMissing => Intl.message(
      'No notification provider is initialized. Check again after app setup.',
      name: 'notifyDiagProviderMissing');
  static String get localProvider => Intl.message(
      'This platform uses local notifications while the app is running. It has no remote push provider in this build.',
      name: 'notifyDiagLocalProvider');
  static String get providerOff => Intl.message(
      'Push notifications are turned off. Review notification settings.',
      name: 'notifyDiagProviderOff');
  static String get noDistributor => Intl.message(
      'UnifiedPush: no compatible distributor was found. Install a distributor, then select it in notification settings.',
      name: 'notifyDiagNoDistributor');
  static String get noSelection => Intl.message(
      'UnifiedPush: the saved distributor is missing or none is selected. Choose an installed distributor in notification settings.',
      name: 'notifyDiagNoSelection');
  static String get noKey => Intl.message(
      'No registration key is saved. Review notification settings.',
      name: 'notifyDiagNoKey');
  static String get otherDistributor =>
      Intl.message('Another installed distributor',
          name: 'notifyDiagOtherDistributor');
  static String get localRegistration => Intl.message(
      'Local notifications on this platform do not use a homeserver pusher.',
      name: 'notifyDiagLocalRegistration');
  static String get registrationSkipped => Intl.message(
      'Check an available push provider and saved registration key first.',
      name: 'notifyDiagRegistrationSkipped');
  static String get accountUnknown =>
      Intl.message('An account or gateway could not be checked.',
          name: 'notifyDiagAccountUnknown');
  static String get registrationUnknown =>
      Intl.message('The server did not return a registration list.',
          name: 'notifyDiagRegistrationUnknown');
  static String get registrationMissing => Intl.message(
      'No registration matches this device’s saved key and configured gateway on this account. Review notification settings.',
      name: 'notifyDiagRegistrationMissing');
  static String get sessionUnknown => Intl.message(
      'A matching registration exists, but its session could not be verified. Delivery remains unverified.',
      name: 'notifyDiagSessionUnknown');
  static String get registered => Intl.message(
      'A registration matches this device and configured gateway on this account. This does not prove that the server sends pushes or that they arrive.',
      name: 'notifyDiagRegistered');
  static String get ntfy => Intl.message('ntfy', name: 'notifyDiagNtfy');
  static String get nextPush =>
      Intl.message('NextPush', name: 'notifyDiagNextPush');
  static String get sunup => Intl.message('Sunup', name: 'notifyDiagSunup');
  static String get fcmDistributor =>
      Intl.message('FCM distributor', name: 'notifyDiagFcmDistributor');
  static String get firebase =>
      Intl.message('Firebase', name: 'notifyDiagFirebase');
  static String providerSaved(String provider) => Intl.message(
      '$provider: registration key is saved; provider availability and reachability were not tested.',
      name: 'notifyDiagProviderSaved',
      args: [provider]);
  static String selected(String distributor) =>
      Intl.message('UnifiedPush · $distributor selected and installed',
          name: 'notifyDiagSelected', args: [distributor]);
  static String result(String status, String detail) =>
      Intl.message('$status · $detail',
          name: 'notifyDiagResult', args: [status, detail]);
}
