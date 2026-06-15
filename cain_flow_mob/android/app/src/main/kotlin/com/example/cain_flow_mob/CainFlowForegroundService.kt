package com.example.cain_flow_mob

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache

class CainFlowForegroundService : Service() {
    private var backgroundEngine: FlutterEngine? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        ensureBackgroundFlutterEngine()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForeground(NOTIFICATION_ID, buildNotification())
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        backgroundEngine?.let { engine ->
            FlutterEngineCache.getInstance().remove(ENGINE_ID)
            engine.destroy()
        }
        backgroundEngine = null

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }

        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun ensureBackgroundFlutterEngine(): FlutterEngine {
        backgroundEngine?.let { return it }

        val flutterLoader = FlutterInjector.instance().flutterLoader()
        flutterLoader.startInitialization(applicationContext)
        flutterLoader.ensureInitializationComplete(applicationContext, emptyArray())

        return FlutterEngine(applicationContext).also { engine ->
            // Leave Dart execution wiring for a later task; this keeps a cached engine ready.
            FlutterEngineCache.getInstance().put(ENGINE_ID, engine)
            backgroundEngine = engine
        }
    }

    private fun buildNotification(): Notification {
        val launchIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or pendingIntentImmutableFlag(),
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("CainFlow is running")
            .setContentText("Background workflow execution is enabled.")
            .setSmallIcon(android.R.drawable.stat_notify_sync)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }

        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(
            CHANNEL_ID,
            CHANNEL_NAME,
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = CHANNEL_DESCRIPTION
        }
        manager.createNotificationChannel(channel)
    }

    private fun pendingIntentImmutableFlag(): Int {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_IMMUTABLE
        } else {
            0
        }
    }

    companion object {
        internal const val ENGINE_ID = "cain_flow_foreground_engine"

        private const val CHANNEL_ID = "cain_flow_foreground_service"
        private const val CHANNEL_NAME = "CainFlow background execution"
        private const val CHANNEL_DESCRIPTION =
            "Keeps CainFlow workflows running in the background."
        private const val NOTIFICATION_ID = 1001

        internal fun start(context: Context) {
            val intent = Intent(context, CainFlowForegroundService::class.java)

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        internal fun stop(context: Context) {
            context.stopService(Intent(context, CainFlowForegroundService::class.java))
        }
    }
}
