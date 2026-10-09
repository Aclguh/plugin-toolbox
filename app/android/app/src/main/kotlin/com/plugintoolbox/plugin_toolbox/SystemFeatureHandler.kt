package com.plugintoolbox.plugin_toolbox

import android.app.Activity
import android.app.KeyguardManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.bluetooth.BluetoothManager
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.hardware.camera2.CameraManager
import android.location.Location
import android.location.LocationManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.nfc.NfcAdapter
import android.os.BatteryManager
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.provider.Settings
import android.view.WindowManager
import androidx.core.app.NotificationCompat
import androidx.core.content.FileProvider
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

class SystemFeatureHandler(
    private val activity: Activity,
    private val getInitialShareData: () -> Map<String, Any>?,
    private val clearInitialShareData: () -> Unit
) : FeatureHandler {
    companion object {
        private const val NOTIFICATION_CHANNEL_ID = "plugin_toolbox_notifications"
    }

    private var nextNotificationId = 1000
    private val mainHandler = Handler(Looper.getMainLooper())
    private val scheduledRunnables = mutableMapOf<Int, Runnable>()

    override fun handleMethodCall(call: MethodCall, result: MethodChannel.Result): Boolean {
        return when (call.method) {
            "shareText" -> {
                val text = call.argument<String>("text") ?: ""
                val subject = call.argument<String?>("subject")
                val intent = Intent(Intent.ACTION_SEND).apply {
                    type = "text/plain"
                    putExtra(Intent.EXTRA_TEXT, text)
                    if (subject != null) {
                        putExtra(Intent.EXTRA_SUBJECT, subject)
                    }
                }
                activity.startActivity(Intent.createChooser(intent, null))
                result.success(true)
                true
            }
            "openUrl" -> {
                val url = call.argument<String>("url") ?: ""
                try {
                    val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
                    activity.startActivity(intent)
                    result.success(true)
                } catch (e: Exception) {
                    result.success(false)
                }
                true
            }
            "setTorch" -> {
                val enabled = call.argument<Boolean>("enabled") ?: false
                try {
                    val cameraManager = activity.getSystemService(Context.CAMERA_SERVICE) as CameraManager
                    val cameraId = cameraManager.cameraIdList[0]
                    cameraManager.setTorchMode(cameraId, enabled)
                    result.success(true)
                } catch (e: Exception) {
                    result.success(false)
                }
                true
            }
            "shareFile" -> {
                val path = call.argument<String>("path") ?: ""
                val mimeType = call.argument<String?>("mimeType") ?: "*/*"
                val subject = call.argument<String?>("subject")
                val file = File(path)
                if (!file.exists()) {
                    result.success(false)
                    return true
                }
                try {
                    val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.fileprovider", file)
                    val intent = Intent(Intent.ACTION_SEND).apply {
                        type = mimeType
                        putExtra(Intent.EXTRA_STREAM, uri)
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        if (subject != null) {
                            putExtra(Intent.EXTRA_SUBJECT, subject)
                        }
                    }
                    activity.startActivity(Intent.createChooser(intent, null))
                    result.success(true)
                } catch (e: Exception) {
                    result.success(false)
                }
                true
            }
            "exportFile" -> {
                val path = call.argument<String>("path") ?: ""
                val defaultName = call.argument<String?>("defaultName") ?: File(path).name
                val file = File(path)
                if (!file.exists()) {
                    result.success(false)
                    return true
                }
                try {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        val values = ContentValues().apply {
                            put(MediaStore.Downloads.DISPLAY_NAME, defaultName)
                            put(MediaStore.Downloads.RELATIVE_PATH, "Download/PluginToolbox")
                            put(MediaStore.Downloads.IS_PENDING, 1)
                        }
                        val resolver = activity.contentResolver
                        val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                        if (uri != null) {
                            resolver.openOutputStream(uri)?.use { out ->
                                file.inputStream().use { input ->
                                    input.copyTo(out)
                                }
                            }
                            values.clear()
                            values.put(MediaStore.Downloads.IS_PENDING, 0)
                            resolver.update(uri, values, null, null)
                            result.success(true)
                        } else {
                            result.success(false)
                        }
                    } else {
                        val downloadsDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
                        val targetDir = File(downloadsDir, "PluginToolbox").apply { mkdirs() }
                        val targetFile = File(targetDir, defaultName)
                        file.copyTo(targetFile, overwrite = true)
                        result.success(true)
                    }
                } catch (e: Exception) {
                    result.success(false)
                }
                true
            }
            "showNotification" -> {
                val title = call.argument<String>("title") ?: "通知"
                val body = call.argument<String>("body") ?: ""
                val id = nextNotificationId++
                val nm = activity.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                ensureNotificationChannel(nm)
                val notif = NotificationCompat.Builder(activity, NOTIFICATION_CHANNEL_ID)
                    .setContentTitle(title)
                    .setContentText(body)
                    .setSmallIcon(R.mipmap.ic_launcher)
                    .setPriority(NotificationCompat.PRIORITY_DEFAULT)
                    .setAutoCancel(true)
                    .build()
                nm.notify(id, notif)
                result.success(id)
                true
            }
            "scheduleNotification" -> {
                val title = call.argument<String>("title") ?: "定时提醒"
                val body = call.argument<String>("body") ?: ""
                val delaySeconds = call.argument<Int>("delaySeconds") ?: 0
                val id = nextNotificationId++
                val nm = activity.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                ensureNotificationChannel(nm)
                val runnable = Runnable {
                    val notif = NotificationCompat.Builder(activity, NOTIFICATION_CHANNEL_ID)
                        .setContentTitle(title)
                        .setContentText(body)
                        .setSmallIcon(R.mipmap.ic_launcher)
                        .setPriority(NotificationCompat.PRIORITY_DEFAULT)
                        .setAutoCancel(true)
                        .build()
                    nm.notify(id, notif)
                    scheduledRunnables.remove(id)
                }
                scheduledRunnables[id] = runnable
                mainHandler.postDelayed(runnable, delaySeconds * 1000L)
                result.success(id)
                true
            }
            "cancelNotification" -> {
                val id = call.argument<Int>("id") ?: -1
                val nm = activity.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                nm.cancel(id)
                scheduledRunnables.remove(id)?.let { mainHandler.removeCallbacks(it) }
                result.success(true)
                true
            }
            "cancelAllNotifications" -> {
                val nm = activity.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                nm.cancelAll()
                scheduledRunnables.values.forEach { mainHandler.removeCallbacks(it) }
                scheduledRunnables.clear()
                result.success(true)
                true
            }
            "getBatteryLevel" -> {
                try {
                    val bm = activity.getSystemService(Context.BATTERY_SERVICE) as BatteryManager
                    val level = bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
                    result.success(level)
                } catch (e: Exception) {
                    result.success(100)
                }
                true
            }
            "isCharging" -> {
                try {
                    val bm = activity.getSystemService(Context.BATTERY_SERVICE) as BatteryManager
                    val status = bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_STATUS)
                    val isCharging = status == BatteryManager.BATTERY_STATUS_CHARGING || status == BatteryManager.BATTERY_STATUS_FULL
                    result.success(isCharging)
                } catch (e: Exception) {
                    result.success(false)
                }
                true
            }
            "getNetworkType" -> {
                try {
                    val cm = activity.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        val net = cm.activeNetwork
                        val caps = cm.getNetworkCapabilities(net)
                        val type = when {
                            caps == null -> "none"
                            caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "wifi"
                            caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "cellular"
                            caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "ethernet"
                            else -> "unknown"
                        }
                        result.success(type)
                    } else {
                        @Suppress("DEPRECATION")
                        val info = cm.activeNetworkInfo
                        val type = when {
                            info == null || !info.isConnected -> "none"
                            info.type == ConnectivityManager.TYPE_WIFI -> "wifi"
                            info.type == ConnectivityManager.TYPE_MOBILE -> "cellular"
                            else -> "unknown"
                        }
                        result.success(type)
                    }
                } catch (e: Exception) {
                    result.success("unknown")
                }
                true
            }
            "isBiometricsAvailable" -> {
                try {
                    val km = activity.getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
                    val isSecure = km?.isDeviceSecure ?: false
                    result.success(isSecure)
                } catch (e: Exception) {
                    result.success(false)
                }
                true
            }
            "authenticateBiometrics" -> {
                try {
                    val km = activity.getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
                    if (km == null || !km.isDeviceSecure) {
                        result.success(mapOf("success" to false, "error" to "Device credentials not set or insecure"))
                    } else {
                        result.success(mapOf("success" to true))
                    }
                } catch (e: Exception) {
                    result.success(mapOf("success" to false, "error" to e.message))
                }
                true
            }
            "setKeepScreenOn" -> {
                val enabled = call.argument<Boolean>("enabled") ?: false
                try {
                    if (enabled) {
                        activity.window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    } else {
                        activity.window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    }
                    result.success(true)
                } catch (e: Exception) {
                    result.success(false)
                }
                true
            }
            "setBrightness" -> {
                val brightness = call.argument<Double>("brightness")?.toFloat() ?: -1f
                try {
                    val lp = activity.window.attributes
                    lp.screenBrightness = brightness.coerceIn(0.01f, 1.0f)
                    activity.window.attributes = lp
                    result.success(true)
                } catch (e: Exception) {
                    result.success(false)
                }
                true
            }
            "getBrightness" -> {
                try {
                    val lp = activity.window.attributes
                    val b = if (lp.screenBrightness < 0f) {
                        try {
                            Settings.System.getInt(
                                activity.contentResolver,
                                Settings.System.SCREEN_BRIGHTNESS
                            ) / 255.0
                        } catch (e: Exception) { 1.0 }
                    } else {
                        lp.screenBrightness.toDouble()
                    }
                    result.success(b)
                } catch (e: Exception) {
                    result.success(1.0)
                }
                true
            }
            "resetBrightness" -> {
                try {
                    val lp = activity.window.attributes
                    lp.screenBrightness = WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE
                    activity.window.attributes = lp
                    result.success(true)
                } catch (e: Exception) {
                    result.success(false)
                }
                true
            }
            "getInitialShare" -> {
                val share = getInitialShareData()
                clearInitialShareData()
                result.success(share)
                true
            }
            "isLocationAvailable" -> {
                try {
                    val lm = activity.getSystemService(Context.LOCATION_SERVICE) as? LocationManager
                    val gps = lm?.isProviderEnabled(LocationManager.GPS_PROVIDER) ?: false
                    val net = lm?.isProviderEnabled(LocationManager.NETWORK_PROVIDER) ?: false
                    result.success(gps || net)
                } catch (e: Exception) {
                    result.success(false)
                }
                true
            }
            "getCurrentPosition" -> {
                try {
                    val lm = activity.getSystemService(Context.LOCATION_SERVICE) as? LocationManager
                    var loc: Location? = null
                    try {
                        if (lm?.isProviderEnabled(LocationManager.GPS_PROVIDER) == true) {
                            loc = lm.getLastKnownLocation(LocationManager.GPS_PROVIDER)
                        }
                        if (loc == null && lm?.isProviderEnabled(LocationManager.NETWORK_PROVIDER) == true) {
                            loc = lm.getLastKnownLocation(LocationManager.NETWORK_PROVIDER)
                        }
                    } catch (e: SecurityException) {}
                    if (loc != null) {
                        result.success(mapOf(
                            "latitude" to loc.latitude,
                            "longitude" to loc.longitude,
                            "altitude" to loc.altitude,
                            "accuracy" to loc.accuracy.toDouble(),
                            "speed" to loc.speed.toDouble(),
                            "timestamp" to loc.time
                        ))
                    } else {
                        result.success(null)
                    }
                } catch (e: Exception) {
                    result.success(null)
                }
                true
            }
            "isNfcAvailable" -> {
                try {
                    val nfcAdapter = NfcAdapter.getDefaultAdapter(activity)
                    result.success(nfcAdapter != null && nfcAdapter.isEnabled)
                } catch (e: Exception) {
                    result.success(false)
                }
                true
            }
            "readNdef" -> {
                result.success(null)
                true
            }
            "writeNdef" -> {
                result.success(false)
                true
            }
            "isBluetoothAvailable" -> {
                try {
                    val bm = activity.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
                    val adapter = bm?.adapter
                    result.success(adapter != null && adapter.isEnabled)
                } catch (e: Exception) {
                    result.success(false)
                }
                true
            }
            "startBluetoothScan" -> {
                result.success(false)
                true
            }
            "stopBluetoothScan" -> {
                result.success(true)
                true
            }
            "connectBluetooth" -> {
                result.success(false)
                true
            }
            "disconnectBluetooth" -> {
                result.success(true)
                true
            }
            "readBluetoothCharacteristic" -> {
                result.success(null)
                true
            }
            "writeBluetoothCharacteristic" -> {
                result.success(false)
                true
            }
            "recognizeText" -> {
                result.success(null)
                true
            }
            else -> false
        }
    }

    private fun ensureNotificationChannel(nm: NotificationManager) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val existing = nm.getNotificationChannel(NOTIFICATION_CHANNEL_ID)
            if (existing == null) {
                val channel = NotificationChannel(
                    NOTIFICATION_CHANNEL_ID,
                    "PluginToolbox 插件通知",
                    NotificationManager.IMPORTANCE_DEFAULT
                ).apply {
                    description = "展示来自 PluginToolbox 动态插件的提醒与通知"
                }
                nm.createNotificationChannel(channel)
            }
        }
    }

    override fun onDestroy() {
        scheduledRunnables.values.forEach { mainHandler.removeCallbacks(it) }
        scheduledRunnables.clear()
    }
}
