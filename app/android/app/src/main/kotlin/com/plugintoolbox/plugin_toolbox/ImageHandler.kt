package com.plugintoolbox.plugin_toolbox

import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Build
import android.provider.MediaStore
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

class ImageHandler(private val context: Context) : FeatureHandler {
    override fun handleMethodCall(call: MethodCall, result: MethodChannel.Result): Boolean {
        return when (call.method) {
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
                true
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
                true
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
                true
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
                true
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
                true
            }
            "saveToGallery" -> {
                val path = call.argument<String>("path") ?: ""
                val file = File(path)
                if (!file.exists()) {
                    result.success(false)
                    return true
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
                    val resolver = context.contentResolver
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
                            context.sendBroadcast(Intent(Intent.ACTION_MEDIA_SCANNER_SCAN_FILE, uri))
                        }
                        result.success(true)
                    } else {
                        result.success(false)
                    }
                } catch (e: Exception) {
                    result.success(false)
                }
                true
            }
            else -> false
        }
    }
}
