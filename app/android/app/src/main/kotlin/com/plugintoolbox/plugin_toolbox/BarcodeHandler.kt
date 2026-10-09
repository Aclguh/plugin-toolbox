package com.plugintoolbox.plugin_toolbox

import android.app.Activity
import android.content.Intent
import android.graphics.BitmapFactory
import android.provider.MediaStore
import androidx.core.content.FileProvider
import com.google.zxing.BinaryBitmap
import com.google.zxing.MultiFormatReader
import com.google.zxing.RGBLuminanceSource
import com.google.zxing.common.HybridBinarizer
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

class BarcodeHandler(private val activity: Activity) : FeatureHandler {
    companion object {
        const val RC_SCAN_INTENT = 1001
        const val RC_SCAN_IMAGE = 1002
    }

    private var pendingScanResult: MethodChannel.Result? = null
    private var scanCaptureFile: File? = null

    override fun handleMethodCall(call: MethodCall, result: MethodChannel.Result): Boolean {
        return when (call.method) {
            "decodeBarcodeFromImage" -> {
                val path = call.argument<String>("path")
                if (path != null) {
                    val decoded = decodeBarcode(path)
                    result.success(decoded)
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
            if (resultCode == Activity.RESULT_OK && scanCaptureFile != null && scanCaptureFile!!.exists()) {
                val decoded = decodeBarcode(scanCaptureFile!!.absolutePath)
                scanCaptureFile?.delete()
                pendingScanResult?.success(decoded)
            } else {
                scanCaptureFile?.delete()
                pendingScanResult?.success(null)
            }
            pendingScanResult = null
            return true
        }
        return false
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
