package com.plugintoolbox.plugin_toolbox

import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationCompat

class NotificationReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getIntExtra("id", 1000)
        val title = intent.getStringExtra("title") ?: "定时提醒"
        val body = intent.getStringExtra("body") ?: ""

        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        SystemFeatureHandler.ensureNotificationChannel(nm)
        val notif = NotificationCompat.Builder(context, SystemFeatureHandler.NOTIFICATION_CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(body)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setAutoCancel(true)
            .build()
        nm.notify(id, notif)
    }
}
