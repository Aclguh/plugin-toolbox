package com.plugintoolbox.plugin_toolbox

import android.app.Activity
import android.content.Intent
import android.graphics.BitmapFactory
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import androidx.core.content.FileProvider
import com.google.zxing.BinaryBitmap
import com.google.zxing.MultiFormatReader
import com.google.zxing.RGBLuminanceSource
import com.google.zxing.common.HybridBinarizer
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

class BarcodeHandler(private val activity: Activity) : FeatureHandler {
    companion object {
        const val RC_SCAN_INTENT = 1001
        const val RC_SCAN_IMAGE = 1002
    }

    private val ioExecutor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private var pendingScanResult: MethodChannel.Result? = null
    private var scanCaptureFile: File? = null

    override fun handleMethodCall(call: MethodCall, result: MethodChannel.Result): Boolean {
        return when (call.method) {
            "decodeBarcodeFromImage" -> {
                val path = call.argument<String>("path")
                if (path != null) {
                    ioExecutor.execute {
                        val decoded = decodeBarcode(path)
                        mainHandler.post { result.success(decoded) }
                    }
                } else {
                    result.success(null)
                }
                true
            }
            "scanBarcode" -> {
                startScanBarcode(result)
                true
            }
            else -> false
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode == RC_SCAN_INTENT) {
            if (resultCode == Activity.RESULT_OK && data != null) {
                val contents = data.getStringExtra("SCAN_RESULT")
                pendingScanResult?.success(contents)
            } else {
                pendingScanResult?.success(null)
            }
            pendingScanResult = null
            return true
        } else if (requestCode == RC_SCAN_IMAGE) {
            val file = scanCaptureFile
            val resultCallback = pendingScanResult
            pendingScanResult = null
            scanCaptureFile = null
            if (resultCode == Activity.RESULT_OK && file != null && file.exists()) {
                ioExecutor.execute {
                    val decoded = decodeBarcode(file.absolutePath)
                    file.delete()
                    mainHandler.post { resultCallback?.success(decoded) }
                }
            } else {
                file?.delete()
                resultCallback?.success(null)
            }
            return true
        }
        return false
    }

    internal fun decodeBarcode(path: String): String? {
        val file = File(path)
        if (!file.exists()) return null
        return try {
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeFile(path, bounds)
            val sampleSize = ImageHandler.calculateInSampleSize(bounds.outWidth, bounds.outHeight, 2048, 2048)
            val opts = BitmapFactory.Options().apply {
                inSampleSize = sampleSize
            }
            val bitmap = BitmapFactory.decodeFile(path, opts) ?: return null
            val intArray = IntArray(bitmap.width * bitmap.height)
            bitmap.getPixels(intArray, 0, bitmap.width, 0, 0, bitmap.width, bitmap.height)
            val source = RGBLuminanceSource(bitmap.width, bitmap.height, intArray)
            val binaryBitmap = BinaryBitmap(HybridBinarizer(source))
            val result = MultiFormatReader().decode(binaryBitmap)
            bitmap.recycle()
            result.text
        } catch (t: Throwable) {
            System.gc()
            null
        }
    }

    override fun onDestroy() {
        ioExecutor.shutdown()
    }

    private fun startScanBarcode(result: MethodChannel.Result) {
        pendingScanResult = result
        try {
            val scanIntent = Intent("com.google.zxing.client.android.SCAN").apply {
                putExtra("SCAN_MODE", "QR_CODE_MODE,PRODUCT_MODE")
            }
            if (scanIntent.resolveActivity(activity.packageManager) != null) {
                activity.startActivityForResult(scanIntent, RC_SCAN_INTENT)
                return
            }

            // 降级使用相机拍照并即时离线解码
            val photoFile = File.createTempFile("scan_", ".jpg", activity.cacheDir)
            scanCaptureFile = photoFile
            val photoUri = FileProvider.getUriForFile(activity, "${activity.packageName}.fileprovider", photoFile)
            val takePictureIntent = Intent(MediaStore.ACTION_IMAGE_CAPTURE).apply {
                putExtra(MediaStore.EXTRA_OUTPUT, photoUri)
                addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            }
            if (takePictureIntent.resolveActivity(activity.packageManager) != null) {
                activity.startActivityForResult(takePictureIntent, RC_SCAN_IMAGE)
            } else {
                pendingScanResult?.success(null)
                pendingScanResult = null
            }
        } catch (e: Exception) {
            pendingScanResult?.success(null)
            pendingScanResult = null
        }
    }
}
