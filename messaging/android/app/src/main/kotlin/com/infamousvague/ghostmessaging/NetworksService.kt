package com.infamousvague.ghostmessaging

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

/**
 * Keeps Ghost running, connected to Signal and Telegram, while it is out of sight (Matt, 2026-11-16, on Ghost
 * notifying for their messages: "Yes, build them"). Their connections live in the app's Dart (lib/inbox: Signal's
 * helper process, Telegram's TDLib), which runs in a Flutter engine kept past the screen (MainActivity
 * provideFlutterEngine); Android keeps the process for as long as a foreground service of the remote-messaging kind
 * runs, as DeskService does for a paired computer. Its notification is the quietest Android allows, on a channel of
 * its own the person can turn off.
 *
 * Started and stopped by Dart as networks are signed in and out (lib/inbox/alerts.dart, through MainActivity's
 * `keepNetworks`). Not restarted by Android if it is stopped: the app opening again connects again.
 */
class NetworksService : Service() {
    companion object {
        private const val CHANNEL = "networks-min"
        private const val NOTIFICATION = 7501

        fun keep(context: Context, names: List<String>) {
            val i = Intent(context.applicationContext, NetworksService::class.java).putStringArrayListExtra("names", ArrayList(names))
            try {
                if (names.isEmpty()) context.applicationContext.stopService(i) else context.applicationContext.startForegroundService(i)
            } catch (e: Exception) {
                // Android refuses a foreground service started from the background at most moments: it starts the next
                // time the app is opened.
                DevLog.add(context, "networks", "the service that keeps ${names.joinToString(" and ")} connected did not start: ${e.message}")
            }
        }

        /** "Signal", "Signal and Telegram", "Signal, Telegram and Bluesky". */
        fun said(names: List<String>): String = when (names.size) {
            0 -> ""
            1 -> names[0]
            else -> names.dropLast(1).joinToString(", ") + " and " + names.last()
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val names = intent?.getStringArrayListExtra("names")?.toList().orEmpty()
        if (names.isEmpty()) {
            stopSelf()
            return START_NOT_STICKY
        }
        val n = notification(names)
        try {
            if (Build.VERSION.SDK_INT >= 34) startForeground(NOTIFICATION, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_REMOTE_MESSAGING)
            else startForeground(NOTIFICATION, n)
        } catch (e: Exception) {
            DevLog.add(this, "networks", "Android refused to keep ${said(names)} connected: ${e.message}")
            stopSelf()
        }
        return START_NOT_STICKY
    }

    private fun notification(names: List<String>): Notification {
        val nm = getSystemService(NotificationManager::class.java)
        if (nm.getNotificationChannel(CHANNEL) == null) {
            nm.createNotificationChannel(NotificationChannel(CHANNEL, "Signal and Telegram connected", NotificationManager.IMPORTANCE_MIN).apply {
                description = "Android asks for a notification while Ghost stays connected to Signal and Telegram. This one is as quiet as Android allows; turn it off here if you like, and their messages still come."
                setShowBadge(false)
                lockscreenVisibility = Notification.VISIBILITY_SECRET
                setSound(null, null)
                enableVibration(false)
            })
        }
        val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        return Notification.Builder(this, CHANNEL)
            .setSmallIcon(R.drawable.ic_stat_ghost)
            .setContentTitle("Connected to ${said(names)}")
            .setContentText("New messages are told to you as they come.")
            .setContentIntent(open)
            .setOngoing(true)
            .setShowWhen(false)
            .setGroup("networks")
            .setCategory(Notification.CATEGORY_SERVICE)
            .setLocalOnly(true)
            .setOnlyAlertOnce(true)
            .setVisibility(Notification.VISIBILITY_SECRET)
            .build()
    }
}
