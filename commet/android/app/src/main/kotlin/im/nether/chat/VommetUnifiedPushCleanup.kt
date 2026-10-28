package im.nether.chat

import android.content.Context
import android.content.Intent
import android.util.Log

// Vommet issue 777: after some updates the UnifiedPush connector (Android
// connector 2.5, inside the unifiedpush plugin) has forgotten its saved
// distributor and registration tokens. It drops them locally when it can't
// find the saved distributor for a moment, without telling the distributor.
// The next registration then makes a new token, so the distributor (e.g.
// Sunup) lists a new registration and keeps the old one forever.
//
// So we remember the connector's tokens ourselves. Whenever a new endpoint
// arrives, any remembered token the connector no longer has is
// unregistered at the distributor it was registered with. A token the
// connector still uses (e.g. kept when switching distributors) is never
// touched, since unregistering it would end the live registration.
object VommetUnifiedPushCleanup {
    // The connector's SharedPreferences (org.unifiedpush.android.connector
    // Constants: PREF_MASTER, PREF_MASTER_INSTANCE, PREF_MASTER_TOKEN,
    // PREF_MASTER_DISTRIBUTOR).
    private const val CONNECTOR_PREFS = "unifiedpush.connector"
    private const val CONNECTOR_INSTANCES = "unifiedpush.instances"
    private const val CONNECTOR_TOKEN = "unifiedpush.connector"
    private const val CONNECTOR_DISTRIBUTOR = "unifiedpush.distributor"
    private const val ACTION_UNREGISTER = "org.unifiedpush.android.distributor.UNREGISTER"
    private const val EXTRA_TOKEN = "token"

    private const val OUR_PREFS = "vommet.unifiedpush"
    private const val OUR_DISTRIBUTOR = "distributor"
    private const val OUR_TOKENS = "tokens"

    /**
     * Unregisters the forgotten tokens; returns how many. Called when a new
     * endpoint arrives (CustomUnifiedPushReceiver), so the current
     * registration is live by then.
     */
    fun removeForgotten(context: Context): Int {
        val connector = context.getSharedPreferences(CONNECTOR_PREFS, Context.MODE_PRIVATE)
        val current = (connector.getStringSet(CONNECTOR_INSTANCES, null) ?: emptySet())
            .mapNotNull { connector.getString("$it/$CONNECTOR_TOKEN", null) }
            .toSet()
        val distributor = connector.getString(CONNECTOR_DISTRIBUTOR, null)

        val ours = context.getSharedPreferences(OUR_PREFS, Context.MODE_PRIVATE)
        val oldDistributor = ours.getString(OUR_DISTRIBUTOR, null)
        val forgotten = (ours.getStringSet(OUR_TOKENS, null) ?: emptySet()) - current

        if (oldDistributor != null) {
            for (token in forgotten) {
                val intent = Intent(ACTION_UNREGISTER)
                intent.`package` = oldDistributor
                intent.putExtra(EXTRA_TOKEN, token)
                context.sendBroadcast(intent)
            }
        }

        val edit = ours.edit()
        if (distributor != null && current.isNotEmpty()) {
            edit.putString(OUR_DISTRIBUTOR, distributor)
            edit.putStringSet(OUR_TOKENS, HashSet(current))
        } else {
            edit.remove(OUR_TOKENS)
        }
        edit.apply()
        val removed = if (oldDistributor != null) forgotten.size else 0
        if (removed > 0) {
            Log.i("VommetUnifiedPush", "unregistered $removed forgotten registration(s)")
        }
        return removed
    }
}
