package im.nether.chat

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.verify.domain.DomainVerificationManager
import android.content.pm.verify.domain.DomainVerificationUserState
import android.net.Uri
import android.os.Build
import android.provider.Settings

// Vommet issue 85: Android 12+ only opens matrix.to links in an app whose
// domain is verified, or that the user allowed under App info > Open by
// default. We can't verify matrix.to, so Settings links to that page.
object VommetOpenByDefault {
    /// Opens the app's "Open by default" page (App info before Android 12).
    fun open(activity: Activity): Boolean {
        val pkg = Uri.parse("package:" + activity.packageName)
        val intents = listOfNotNull(
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S)
                Intent(Settings.ACTION_APP_OPEN_BY_DEFAULT_SETTINGS, pkg) else null,
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, pkg),
        )
        for (intent in intents) {
            try {
                activity.startActivity(intent)
                return true
            } catch (e: ActivityNotFoundException) {
                // Some vendor builds lack the page; try the next one.
            }
        }
        return false
    }

    /// Whether matrix.to links open here; null before Android 12, where
    /// Android asks which app should open them.
    fun matrixToAllowed(context: Context): Boolean? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return null
        val manager = context.getSystemService(DomainVerificationManager::class.java) ?: return null
        val state = try {
            manager.getDomainVerificationUserState(context.packageName)
        } catch (e: PackageManager.NameNotFoundException) {
            null
        } ?: return null
        val host = state.hostToStateMap["matrix.to"] ?: return null
        return state.isLinkHandlingAllowed &&
            host != DomainVerificationUserState.DOMAIN_STATE_NONE
    }
}
