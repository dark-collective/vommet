// Vommet: redacted mode's switches as stored in preferences (Vommet issue 400).

import 'package:commet/config/vommet_preferences.dart';
import 'package:commet/utils/redaction/redaction_policy.dart';

extension RedactionPreferences on VommetPreferences {
  /// Redaction applies: the experiment is on and the user turned it on.
  bool get redactionActive =>
      experimentRedactedMode.value && redactionEnabled.value;

  /// The switches as stored, whether or not redaction is on.
  RedactionSettings get redactionSwitches => RedactionSettings(
        names: NameRedaction.values.asNameMap()[redactionNames.value] ??
            NameRedaction.hide,
        avatars: redactionAvatars.value,
        text: TextRedaction.values.asNameMap()[redactionText.value] ??
            TextRedaction.keep,
        distinguishable: redactionDistinguishable.value,
        roomNames: redactionRoomNames.value,
        images: redactionImages.value,
      );

  /// What is redacted right now.
  RedactionSettings get effectiveRedaction =>
      redactionActive ? redactionSwitches : RedactionSettings.off;

  Future<void> setRedactionSwitches(RedactionSettings settings) async {
    await redactionNames.set(settings.names.name);
    await redactionAvatars.set(settings.avatars);
    await redactionText.set(settings.text.name);
    await redactionDistinguishable.set(settings.distinguishable);
    await redactionRoomNames.set(settings.roomNames);
    await redactionImages.set(settings.images);
  }
}
