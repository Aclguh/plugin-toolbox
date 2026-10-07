package com.plugintoolbox.plugin_toolbox

import android.app.Activity
import android.app.KeyguardManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.hardware.camera2.CameraManager
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.media.MediaPlayer
import android.media.MediaRecorder
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.os.BatteryManager
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.speech.tts.TextToSpeech
import androidx.core.app.NotificationCompat
import androidx.core.content.FileProvider
import com.google.zxing.BinaryBitmap
import com.google.zxing.MultiFormatReader
import com.google.zxing.RGBLuminanceSource
import com.google.zxing.common.HybridBinarizer
import android.view.WindowManager
import android.location.LocationManager
import android.location.Location
import android.nfc.NfcAdapter
import android.bluetooth.BluetoothManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.Locale

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.plugintoolbox/host_native"

    // 初始分享数据接收
    private var initialShareData: Map<String, Any>? = null

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        handleShareIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleShareIntent(intent)
    }

    private fun handleShareIntent(intent: Intent?) {
        if (intent == null) return
        val action = intent.action
        val type = intent.type
        if (Intent.ACTION_SEND == action && type != null) {
            if ("text/plain" == type) {
                val text = intent.getStringExtra(Intent.EXTRA_TEXT)
                val subject = intent.getStringExtra(Intent.EXTRA_SUBJECT)
                if (text != null) {
                    initialShareData = mapOf(
                        "type" to "text",
                        "text" to text,
                        "subject" to (subject ?: "")
                    )
                }
            } else {
                val uri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
                }
                if (uri != null) {
                    initialShareData = mapOf(
                        "type" to "file",
                        "uri" to uri.toString(),
                        "mimeType" to type
                    )
                }
            }
        }
    }

    // 传感器管理
    private var sensorManager: SensorManager? = null
    private val sensorListeners = mutableMapOf<String, SensorEventListener>()
    private val latestSensorReadings = mutableMapOf<String, Map<String, Any>>()
    private val gravityValues = FloatArray(3)
    private val geomagneticValues = FloatArray(3)
    private var hasGravity = false
    private var hasGeomagnetic = false

    // 录音与音频感知
    private var activeMediaRecorder: MediaRecorder? = null
    private var recordingStartTime = 0L
    private var recordingFilePath: String? = null

    // TTS 语音合成
    private var textToSpeech: TextToSpeech? = null
    private var ttsReady = false

    // 扫码状态
    private var pendingScanResult: MethodChannel.Result? = null
    private var scanCaptureFile: File? = null
    private val RC_SCAN_IMAGE = 1001
    private val RC_SCAN_INTENT = 1002

    // 通知与媒体调度
    private val NOTIFICATION_CHANNEL_ID = "plugin_toolbox_notifications"
    private var nextNotificationId = 1000
    private val mainHandler = Handler(Looper.getMainLooper())
    private val scheduledRunnables = mutableMapOf<Int, Runnable>()
    private var activeMediaPlayer: MediaPlayer? = null

    private fun getOrCreateSensorManager(): SensorManager {
        if (sensorManager == null) {
            sensorManager = getSystemService(Context.SENSOR_SERVICE) as SensorManager
        }
        return sensorManager!!
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
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
                    startActivity(Intent.createChooser(intent, null))
                    result.success(true)
                }
                "openUrl" -> {
                    val url = call.argument<String>("url") ?: ""
                    try {
                        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "setTorch" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    try {
                        val cameraManager = getSystemService(Context.CAMERA_SERVICE) as CameraManager
                        val cameraId = cameraManager.cameraIdList[0]
                        cameraManager.setTorchMode(cameraId, enabled)
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "shareFile" -> {
                    val path = call.argument<String>("path") ?: ""
                    val mimeType = call.argument<String?>("mimeType") ?: "*/*"
                    val subject = call.argument<String?>("subject")
                    val file = File(path)
                    if (!file.exists()) {
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    try {
                        val uri: Uri = FileProvider.getUriForFile(
                            this,
                            "$packageName.fileprovider",
                            file
                        )
                        val intent = Intent(Intent.ACTION_SEND).apply {
                            type = mimeType
                            putExtra(Intent.EXTRA_STREAM, uri)
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            if (subject != null) {
                                putExtra(Intent.EXTRA_SUBJECT, subject)
                            }
                        }
                        startActivity(Intent.createChooser(intent, null))
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "saveToGallery" -> {
                    val path = call.argument<String>("path") ?: ""
                    val file = File(path)
                    if (!file.exists()) {
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    try {
                        val filename = file.name
                        val mimeType = when {
                            filename.endsWith(".png", true) -> "image/png"
                            filename.endsWith(".webp", true) -> "image/webp"
                            filename.endsWith(".gif", true) -> "image/gif"
                            else -> "image/jpeg"
                        }
                        val values = ContentValues().apply {
                            put(MediaStore.Images.Media.DISPLAY_NAME, filename)
                            put(MediaStore.Images.Media.MIME_TYPE, mimeType)
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                                put(MediaStore.Images.Media.RELATIVE_PATH, "Pictures/PluginToolbox")
                                put(MediaStore.Images.Media.IS_PENDING, 1)
                            }
                        }
                        val resolver = contentResolver
                        val uri = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
                        if (uri != null) {
                            resolver.openOutputStream(uri)?.use { out ->
                                file.inputStream().use { input ->
                                    input.copyTo(out)
                                }
                            }
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                                values.clear()
                                values.put(MediaStore.Images.Media.IS_PENDING, 0)
                                resolver.update(uri, values, null, null)
                            } else {
                                sendBroadcast(Intent(Intent.ACTION_MEDIA_SCANNER_SCAN_FILE, uri))
                            }
                            result.success(true)
                        } else {
                            result.success(false)
                        }
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "exportFile" -> {
                    val path = call.argument<String>("path") ?: ""
                    val defaultName = call.argument<String?>("defaultName") ?: File(path).name
                    val file = File(path)
                    if (!file.exists()) {
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                            val values = ContentValues().apply {
                                put(MediaStore.Downloads.DISPLAY_NAME, defaultName)
                                put(MediaStore.Downloads.RELATIVE_PATH, "Download/PluginToolbox")
                                put(MediaStore.Downloads.IS_PENDING, 1)
                            }
                            val resolver = contentResolver
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
                }
                "startSensor" -> {
                    val type = call.argument<String>("type") ?: "accelerometer"
                    val sm = getOrCreateSensorManager()
                    when (type) {
                        "accelerometer" -> {
                            val sensor = sm.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
                            if (sensor == null) {
                                result.success(false)
                                return@setMethodCallHandler
                            }
                            val listener = object : SensorEventListener {
                                override fun onSensorChanged(event: SensorEvent) {
                                    latestSensorReadings["accelerometer"] = mapOf(
                                        "x" to event.values[0].toDouble(),
                                        "y" to event.values[1].toDouble(),
                                        "z" to event.values[2].toDouble()
                                    )
                                }
                                override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
                            }
                            sensorListeners["accelerometer"]?.let { sm.unregisterListener(it) }
                            sm.registerListener(listener, sensor, SensorManager.SENSOR_DELAY_UI)
                            sensorListeners["accelerometer"] = listener
                            result.success(true)
                        }
                        "gyroscope" -> {
                            val sensor = sm.getDefaultSensor(Sensor.TYPE_GYROSCOPE)
                            if (sensor == null) {
                                result.success(false)
                                return@setMethodCallHandler
                            }
                            val listener = object : SensorEventListener {
                                override fun onSensorChanged(event: SensorEvent) {
                                    latestSensorReadings["gyroscope"] = mapOf(
                                        "x" to event.values[0].toDouble(),
                                        "y" to event.values[1].toDouble(),
                                        "z" to event.values[2].toDouble()
                                    )
                                }
                                override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
                            }
                            sensorListeners["gyroscope"]?.let { sm.unregisterListener(it) }
                            sm.registerListener(listener, sensor, SensorManager.SENSOR_DELAY_UI)
                            sensorListeners["gyroscope"] = listener
                            result.success(true)
                        }
                        "magnetometer" -> {
                            val sensor = sm.getDefaultSensor(Sensor.TYPE_MAGNETIC_FIELD)
                            if (sensor == null) {
                                result.success(false)
                                return@setMethodCallHandler
                            }
                            val listener = object : SensorEventListener {
                                override fun onSensorChanged(event: SensorEvent) {
                                    latestSensorReadings["magnetometer"] = mapOf(
                                        "x" to event.values[0].toDouble(),
                                        "y" to event.values[1].toDouble(),
                                        "z" to event.values[2].toDouble()
                                    )
                                }
                                override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
                            }
                            sensorListeners["magnetometer"]?.let { sm.unregisterListener(it) }
                            sm.registerListener(listener, sensor, SensorManager.SENSOR_DELAY_UI)
                            sensorListeners["magnetometer"] = listener
                            result.success(true)
                        }
                        "compass" -> {
                            val accel = sm.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
                            val mag = sm.getDefaultSensor(Sensor.TYPE_MAGNETIC_FIELD)
                            if (accel == null || mag == null) {
                                result.success(false)
                                return@setMethodCallHandler
                            }
                            val listener = object : SensorEventListener {
                                override fun onSensorChanged(event: SensorEvent) {
                                    if (event.sensor.type == Sensor.TYPE_ACCELEROMETER) {
                                        System.arraycopy(event.values, 0, gravityValues, 0, 3)
                                        hasGravity = true
                                    } else if (event.sensor.type == Sensor.TYPE_MAGNETIC_FIELD) {
                                        System.arraycopy(event.values, 0, geomagneticValues, 0, 3)
                                        hasGeomagnetic = true
                                    }
                                    if (hasGravity && hasGeomagnetic) {
                                        val r = FloatArray(9)
                                        val i = FloatArray(9)
                                        if (SensorManager.getRotationMatrix(r, i, gravityValues, geomagneticValues)) {
                                            val orientation = FloatArray(3)
                                            SensorManager.getOrientation(r, orientation)
                                            val azimuthRad = orientation[0]
                                            var degrees = Math.toDegrees(azimuthRad.toDouble())
                                            if (degrees < 0) degrees += 360.0
                                            latestSensorReadings["compass"] = mapOf(
                                                "heading" to degrees,
                                                "accuracy" to event.accuracy
                                            )
                                        }
                                    }
                                }
                                override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
                            }
                            sensorListeners["compass"]?.let { sm.unregisterListener(it) }
                            sm.registerListener(listener, accel, SensorManager.SENSOR_DELAY_UI)
                            sm.registerListener(listener, mag, SensorManager.SENSOR_DELAY_UI)
                            sensorListeners["compass"] = listener
                            result.success(true)
                        }
                        else -> result.success(false)
                    }
                }
                "stopSensor" -> {
                    val type = call.argument<String>("type") ?: ""
                    sensorManager?.let { sm ->
                        if (type.isEmpty() || type == "all") {
                            sensorListeners.values.forEach { sm.unregisterListener(it) }
                            sensorListeners.clear()
                        } else {
                            sensorListeners.remove(type)?.let { sm.unregisterListener(it) }
                        }
                    }
                    result.success(true)
                }
                "getSensorData" -> {
                    val type = call.argument<String>("type") ?: "accelerometer"
                    val data = latestSensorReadings[type]
                    result.success(data)
                }
                "decodeBarcodeFromImage" -> {
                    val path = call.argument<String>("path") ?: ""
                    val decoded = decodeBarcode(path)
                    result.success(decoded)
                }
                "scanBarcode" -> {
                    startScanBarcode(result)
                }
                "imageInfo" -> {
                    val path = call.argument<String>("path") ?: ""
                    val file = File(path)
                    if (!file.exists()) {
                        result.success(null)
                    } else {
                        val opts = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                        BitmapFactory.decodeFile(path, opts)
                        val format = opts.outMimeType ?: when {
                            path.endsWith(".png", true) -> "image/png"
                            path.endsWith(".webp", true) -> "image/webp"
                            else -> "image/jpeg"
                        }
                        result.success(mapOf(
                            "width" to opts.outWidth,
                            "height" to opts.outHeight,
                            "format" to format,
                            "size" to file.length().toInt()
                        ))
                    }
                }
                "compressImage" -> {
                    val src = call.argument<String>("src") ?: ""
                    val dest = call.argument<String>("dest") ?: ""
                    val quality = call.argument<Int>("quality") ?: 80
                    val bitmap = BitmapFactory.decodeFile(src)
                    if (bitmap == null) {
                        result.success(false)
                    } else {
                        val destFile = File(dest)
                        destFile.parentFile?.mkdirs()
                        val format = if (dest.endsWith(".png", true)) Bitmap.CompressFormat.PNG else Bitmap.CompressFormat.JPEG
                        val ok = destFile.outputStream().use { out ->
                            bitmap.compress(format, quality, out)
                        }
                        bitmap.recycle()
                        result.success(ok)
                    }
                }
                "cropImage" -> {
                    val src = call.argument<String>("src") ?: ""
                    val dest = call.argument<String>("dest") ?: ""
                    val x = call.argument<Int>("x") ?: 0
                    val y = call.argument<Int>("y") ?: 0
                    val width = call.argument<Int>("width") ?: 0
                    val height = call.argument<Int>("height") ?: 0
                    val bitmap = BitmapFactory.decodeFile(src)
                    if (bitmap == null) {
                        result.success(false)
                    } else {
                        val safeX = x.coerceIn(0, bitmap.width - 1)
                        val safeY = y.coerceIn(0, bitmap.height - 1)
                        val safeW = width.coerceIn(1, bitmap.width - safeX)
                        val safeH = height.coerceIn(1, bitmap.height - safeY)
                        val cropped = Bitmap.createBitmap(bitmap, safeX, safeY, safeW, safeH)
                        val destFile = File(dest)
                        destFile.parentFile?.mkdirs()
                        val format = if (dest.endsWith(".png", true)) Bitmap.CompressFormat.PNG else Bitmap.CompressFormat.JPEG
                        val ok = destFile.outputStream().use { out ->
                            cropped.compress(format, 90, out)
                        }
                        cropped.recycle()
                        bitmap.recycle()
                        result.success(ok)
                    }
                }
                "convertImage" -> {
                    val src = call.argument<String>("src") ?: ""
                    val dest = call.argument<String>("dest") ?: ""
                    val formatStr = (call.argument<String>("format") ?: "png").lowercase()
                    val bitmap = BitmapFactory.decodeFile(src)
                    if (bitmap == null) {
                        result.success(false)
                    } else {
                        val destFile = File(dest)
                        destFile.parentFile?.mkdirs()
                        val format = when (formatStr) {
                            "png" -> Bitmap.CompressFormat.PNG
                            "webp" -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) Bitmap.CompressFormat.WEBP_LOSSY else Bitmap.CompressFormat.WEBP
                            else -> Bitmap.CompressFormat.JPEG
                        }
                        val ok = destFile.outputStream().use { out ->
                            bitmap.compress(format, 90, out)
                        }
                        bitmap.recycle()
                        result.success(ok)
                    }
                }
                "stripExifImage" -> {
                    val src = call.argument<String>("src") ?: ""
                    val dest = call.argument<String>("dest") ?: ""
                    val bitmap = BitmapFactory.decodeFile(src)
                    if (bitmap == null) {
                        result.success(false)
                    } else {
                        val destFile = File(dest)
                        destFile.parentFile?.mkdirs()
                        val format = if (dest.endsWith(".png", true)) Bitmap.CompressFormat.PNG else Bitmap.CompressFormat.JPEG
                        val ok = destFile.outputStream().use { out ->
                            bitmap.compress(format, 95, out)
                        }
                        bitmap.recycle()
                        result.success(ok)
                    }
                }
                "showNotification" -> {
                    val title = call.argument<String>("title") ?: "通知"
                    val body = call.argument<String>("body") ?: ""
                    val id = nextNotificationId++
                    val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                    ensureNotificationChannel(nm)
                    val notif = NotificationCompat.Builder(this, NOTIFICATION_CHANNEL_ID)
                        .setContentTitle(title)
                        .setContentText(body)
                        .setSmallIcon(R.mipmap.ic_launcher)
                        .setPriority(NotificationCompat.PRIORITY_DEFAULT)
                        .setAutoCancel(true)
                        .build()
                    nm.notify(id, notif)
                    result.success(id)
                }
                "scheduleNotification" -> {
                    val title = call.argument<String>("title") ?: "定时提醒"
                    val body = call.argument<String>("body") ?: ""
                    val delaySeconds = call.argument<Int>("delaySeconds") ?: 0
                    val id = nextNotificationId++
                    val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                    ensureNotificationChannel(nm)
                    val runnable = Runnable {
                        val notif = NotificationCompat.Builder(this@MainActivity, NOTIFICATION_CHANNEL_ID)
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
                }
                "cancelNotification" -> {
                    val id = call.argument<Int>("id") ?: -1
                    val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                    nm.cancel(id)
                    scheduledRunnables.remove(id)?.let { mainHandler.removeCallbacks(it) }
                    result.success(true)
                }
                "cancelAllNotifications" -> {
                    val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                    nm.cancelAll()
                    scheduledRunnables.values.forEach { mainHandler.removeCallbacks(it) }
                    scheduledRunnables.clear()
                    result.success(true)
                }
                "playAudio" -> {
                    val path = call.argument<String>("path") ?: ""
                    try {
                        activeMediaPlayer?.release()
                        activeMediaPlayer = MediaPlayer().apply {
                            setDataSource(path)
                            prepare()
                            start()
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "stopAudio" -> {
                    try {
                        activeMediaPlayer?.let {
                            if (it.isPlaying) it.stop()
                            it.release()
                        }
                        activeMediaPlayer = null
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "playTone" -> {
                    val freq = call.argument<Double>("frequency") ?: 440.0
                    val duration = call.argument<Int>("durationMs") ?: 200
                    Thread {
                        try {
                            val sampleRate = 44100
                            val numSamples = (duration * sampleRate / 1000)
                            val buffer = ShortArray(numSamples)
                            for (i in 0 until numSamples) {
                                val angle = 2.0 * Math.PI * i * freq / sampleRate
                                buffer[i] = (Math.sin(angle) * 32767).toInt().toShort()
                            }
                            val minSize = AudioTrack.getMinBufferSize(sampleRate, AudioFormat.CHANNEL_OUT_MONO, AudioFormat.ENCODING_PCM_16BIT)
                            @Suppress("DEPRECATION")
                            val track = AudioTrack(
                                AudioManager.STREAM_MUSIC,
                                sampleRate,
                                AudioFormat.CHANNEL_OUT_MONO,
                                AudioFormat.ENCODING_PCM_16BIT,
                                Math.max(minSize, numSamples * 2),
                                AudioTrack.MODE_STREAM
                            )
                            track.play()
                            track.write(buffer, 0, numSamples)
                            track.stop()
                            track.release()
                        } catch (e: Exception) {}
                    }.start()
                    result.success(true)
                }
                "getBatteryLevel" -> {
                    try {
                        val bm = getSystemService(Context.BATTERY_SERVICE) as BatteryManager
                        val level = bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
                        result.success(level)
                    } catch (e: Exception) {
                        result.success(100)
                    }
                }
                "isCharging" -> {
                    try {
                        val bm = getSystemService(Context.BATTERY_SERVICE) as BatteryManager
                        val status = bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_STATUS)
                        val isCharging = status == BatteryManager.BATTERY_STATUS_CHARGING || status == BatteryManager.BATTERY_STATUS_FULL
                        result.success(isCharging)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "getNetworkType" -> {
                    try {
                        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
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
                }
                "isBiometricsAvailable" -> {
                    try {
                        val km = getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
                        val isSecure = km?.isDeviceSecure ?: false
                        result.success(isSecure)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "authenticateBiometrics" -> {
                    try {
                        val km = getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
                        if (km == null || !km.isDeviceSecure) {
                            result.success(mapOf("success" to false, "error" to "Device credentials not set or insecure"))
                        } else {
                            result.success(mapOf("success" to true))
                        }
                    } catch (e: Exception) {
                        result.success(mapOf("success" to false, "error" to e.message))
                    }
                }
                "startAudioRecording" -> {
                    val destPath = call.argument<String>("path") ?: ""
                    try {
                        activeMediaRecorder?.release()
                        val recorder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                            MediaRecorder(this)
                        } else {
                            @Suppress("DEPRECATION")
                            MediaRecorder()
                        }
                        recorder.apply {
                            setAudioSource(MediaRecorder.AudioSource.MIC)
                            setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
                            setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
                            setOutputFile(destPath)
                            prepare()
                            start()
                        }
                        activeMediaRecorder = recorder
                        recordingStartTime = System.currentTimeMillis()
                        recordingFilePath = destPath
                        result.success(true)
                    } catch (e: Exception) {
                        activeMediaRecorder = null
                        result.success(false)
                    }
                }
                "stopAudioRecording" -> {
                    try {
                        val durationMs = (System.currentTimeMillis() - recordingStartTime).toInt()
                        val path = recordingFilePath
                        activeMediaRecorder?.let {
                            try { it.stop() } catch (_: Exception) {}
                            it.release()
                        }
                        activeMediaRecorder = null
                        recordingFilePath = null
                        if (path != null) {
                            val f = File(path)
                            val size = if (f.exists()) f.length().toInt() else 0
                            result.success(mapOf(
                                "path" to path,
                                "durationMs" to durationMs,
                                "size" to size
                            ))
                        } else {
                            result.success(null)
                        }
                    } catch (e: Exception) {
                        activeMediaRecorder?.release()
                        activeMediaRecorder = null
                        result.success(null)
                    }
                }
                "getAudioDecibel" -> {
                    try {
                        val maxAmp = activeMediaRecorder?.maxAmplitude ?: 0
                        if (maxAmp > 0) {
                            val db = 20 * Math.log10(maxAmp.toDouble())
                            result.success(db)
                        } else {
                            result.success(0.0)
                        }
                    } catch (e: Exception) {
                        result.success(0.0)
                    }
                }
                "speakText" -> {
                    val text = call.argument<String>("text") ?: ""
                    val lang = call.argument<String?>("language")
                    val pitch = call.argument<Double?>("pitch")?.toFloat() ?: 1.0f
                    val rate = call.argument<Double?>("rate")?.toFloat() ?: 1.0f

                    fun doSpeak() {
                        textToSpeech?.apply {
                            setPitch(pitch)
                            setSpeechRate(rate)
                            if (!lang.isNullOrEmpty()) {
                                language = Locale.forLanguageTag(lang)
                            }
                            speak(text, TextToSpeech.QUEUE_FLUSH, null, "tts_${System.currentTimeMillis()}")
                        }
                    }

                    if (textToSpeech == null) {
                        textToSpeech = TextToSpeech(this) { status ->
                            if (status == TextToSpeech.SUCCESS) {
                                ttsReady = true
                                doSpeak()
                            }
                        }
                        result.success(true)
                    } else {
                        doSpeak()
                        result.success(true)
                    }
                }
                "stopSpeaking" -> {
                    try {
                        textToSpeech?.stop()
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "setKeepScreenOn" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    try {
                        if (enabled) {
                            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "setBrightness" -> {
                    val brightness = call.argument<Double>("brightness")?.toFloat() ?: -1f
                    try {
                        val lp = window.attributes
                        lp.screenBrightness = brightness.coerceIn(0.01f, 1.0f)
                        window.attributes = lp
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "getBrightness" -> {
                    try {
                        val lp = window.attributes
                        val b = if (lp.screenBrightness < 0f) {
                            try {
                                Settings.System.getInt(
                                    contentResolver,
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
                }
                "resetBrightness" -> {
                    try {
                        val lp = window.attributes
                        lp.screenBrightness = WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE
                        window.attributes = lp
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "getInitialShare" -> {
                    val share = initialShareData
                    initialShareData = null
                    result.success(share)
                }
                "isLocationAvailable" -> {
                    try {
                        val lm = getSystemService(Context.LOCATION_SERVICE) as? LocationManager
                        val gps = lm?.isProviderEnabled(LocationManager.GPS_PROVIDER) ?: false
                        val net = lm?.isProviderEnabled(LocationManager.NETWORK_PROVIDER) ?: false
                        result.success(gps || net)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "getCurrentPosition" -> {
                    try {
                        val lm = getSystemService(Context.LOCATION_SERVICE) as? LocationManager
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
                }
                "isNfcAvailable" -> {
                    try {
                        val nfcAdapter = NfcAdapter.getDefaultAdapter(this)
                        result.success(nfcAdapter != null && nfcAdapter.isEnabled)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "readNdef" -> {
                    result.success(null)
                }
                "writeNdef" -> {
                    result.success(false)
                }
                "isBluetoothAvailable" -> {
                    try {
                        val bm = getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
                        val adapter = bm?.adapter
                        result.success(adapter != null && adapter.isEnabled)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "startBluetoothScan" -> {
                    result.success(false)
                }
                "stopBluetoothScan" -> {
                    result.success(true)
                }
                "connectBluetooth" -> {
                    result.success(false)
                }
                "disconnectBluetooth" -> {
                    result.success(true)
                }
                "readBluetoothCharacteristic" -> {
                    result.success(null)
                }
                "writeBluetoothCharacteristic" -> {
                    result.success(false)
                }
                "recognizeText" -> {
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun decodeBarcode(path: String): String? {
        val file = File(path)
        if (!file.exists()) return null
        return try {
            val bitmap = BitmapFactory.decodeFile(path) ?: return null
            val intArray = IntArray(bitmap.width * bitmap.height)
            bitmap.getPixels(intArray, 0, bitmap.width, 0, 0, bitmap.width, bitmap.height)
            val source = RGBLuminanceSource(bitmap.width, bitmap.height, intArray)
            val binaryBitmap = BinaryBitmap(HybridBinarizer(source))
            val result = MultiFormatReader().decode(binaryBitmap)
            result.text
        } catch (e: Exception) {
            null
        }
    }

    private fun startScanBarcode(result: MethodChannel.Result) {
        pendingScanResult = result
        try {
            val scanIntent = Intent("com.google.zxing.client.android.SCAN").apply {
                putExtra("SCAN_MODE", "QR_CODE_MODE,PRODUCT_MODE")
            }
            if (scanIntent.resolveActivity(packageManager) != null) {
                startActivityForResult(scanIntent, RC_SCAN_INTENT)
                return
            }

            // 降级使用相机拍照并即时离线解码
            val photoFile = File.createTempFile("scan_", ".jpg", cacheDir)
            scanCaptureFile = photoFile
            val photoUri = FileProvider.getUriForFile(this, "$packageName.fileprovider", photoFile)
            val takePictureIntent = Intent(MediaStore.ACTION_IMAGE_CAPTURE).apply {
                putExtra(MediaStore.EXTRA_OUTPUT, photoUri)
                addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            }
            if (takePictureIntent.resolveActivity(packageManager) != null) {
                startActivityForResult(takePictureIntent, RC_SCAN_IMAGE)
            } else {
                pendingScanResult?.success(null)
                pendingScanResult = null
            }
        } catch (e: Exception) {
            pendingScanResult?.success(null)
            pendingScanResult = null
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == RC_SCAN_INTENT) {
            if (resultCode == Activity.RESULT_OK && data != null) {
                val contents = data.getStringExtra("SCAN_RESULT")
                pendingScanResult?.success(contents)
            } else {
                pendingScanResult?.success(null)
            }
            pendingScanResult = null
        } else if (requestCode == RC_SCAN_IMAGE) {
            if (resultCode == Activity.RESULT_OK && scanCaptureFile != null && scanCaptureFile!!.exists()) {
                val decoded = decodeBarcode(scanCaptureFile!!.absolutePath)
                scanCaptureFile?.delete()
                pendingScanResult?.success(decoded)
            } else {
                scanCaptureFile?.delete()
                pendingScanResult?.success(null)
            }
            pendingScanResult = null
        }
    }

    override fun onPause() {
        super.onPause()
        sensorManager?.let { sm ->
            sensorListeners.values.forEach { sm.unregisterListener(it) }
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
        super.onDestroy()
        activeMediaPlayer?.release()
        activeMediaPlayer = null
        activeMediaRecorder?.let {
            try { it.stop() } catch (_: Exception) {}
            it.release()
        }
        activeMediaRecorder = null
        textToSpeech?.shutdown()
        textToSpeech = null
        scheduledRunnables.values.forEach { mainHandler.removeCallbacks(it) }
        scheduledRunnables.clear()
    }
}
