package com.plugintoolbox.plugin_toolbox

import android.app.Activity
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.hardware.camera2.CameraManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import androidx.core.content.FileProvider
import com.google.zxing.BinaryBitmap
import com.google.zxing.MultiFormatReader
import com.google.zxing.RGBLuminanceSource
import com.google.zxing.common.HybridBinarizer
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.plugintoolbox/host_native"

    // 传感器管理
    private var sensorManager: SensorManager? = null
    private val sensorListeners = mutableMapOf<String, SensorEventListener>()
    private val latestSensorReadings = mutableMapOf<String, Map<String, Any>>()
    private val gravityValues = FloatArray(3)
    private val geomagneticValues = FloatArray(3)
    private var hasGravity = false
    private var hasGeomagnetic = false

    // 扫码状态
    private var pendingScanResult: MethodChannel.Result? = null
    private var scanCaptureFile: File? = null
    private val RC_SCAN_IMAGE = 1001
    private val RC_SCAN_INTENT = 1002

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
}
