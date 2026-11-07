package im.nether.chat

import android.app.Activity
import android.content.Intent

/// Vommet issue 595: reopening Vommet from Recents relaunches the activity
/// with the intent that first started it. If that was a notification tap,
/// the plugins hand it to Dart again and the app jumps to that old
/// notification's room. Swap it for a plain launch intent before the
/// plugins attach (provideFlutterEngine runs just before they do).
fun dropReplayedNotificationIntent(activity: Activity) {
    val intent = activity.intent ?: return
    val fromHistory = (intent.flags and
        Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY) != 0
    if (!fromHistory) return
    val opensRoom = intent.action == "SELECT_NOTIFICATION" ||
        intent.hasExtra("flutter_shortcuts_new")
    if (!opensRoom) return
    activity.intent = Intent(intent).apply {
        action = Intent.ACTION_MAIN
        replaceExtras(null as android.os.Bundle?)
    }
}
