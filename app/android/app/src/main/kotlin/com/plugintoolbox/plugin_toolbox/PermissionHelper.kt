package com.plugintoolbox.plugin_toolbox

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import java.util.concurrent.atomic.AtomicInteger

/**
 * Android 运行时动态权限管理辅助类。
 * 负责权限检测、动态申请请求码派发以及异步结果回调映射。
 */
class PermissionHelper(private val activity: Activity) {

    private val requestCodeGenerator = AtomicInteger(5000)
    private val pendingCallbacks = mutableMapOf<Int, (Boolean) -> Unit>()

    fun hasPermission(permission: String): Boolean {
        return ContextCompat.checkSelfPermission(
            activity,
            permission
        ) == PackageManager.PERMISSION_GRANTED
    }

    fun hasPermissions(permissions: Array<String>): Boolean {
        return permissions.all { hasPermission(it) }
    }

    fun getPermissionsForFeature(feature: String): Array<String> {
        return when (feature.lowercase()) {
            "location" -> arrayOf(
                Manifest.permission.ACCESS_FINE_LOCATION,
                Manifest.permission.ACCESS_COARSE_LOCATION
            )
            "audio", "record_audio", "microphone" -> arrayOf(
                Manifest.permission.RECORD_AUDIO
            )
            "camera" -> arrayOf(
                Manifest.permission.CAMERA
            )
            "notification", "notifications" -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    arrayOf(Manifest.permission.POST_NOTIFICATIONS)
                } else {
                    emptyArray()
                }
            }
            "bluetooth" -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    arrayOf(
                        Manifest.permission.BLUETOOTH_SCAN,
                        Manifest.permission.BLUETOOTH_CONNECT
                    )
                } else {
                    arrayOf(
                        Manifest.permission.BLUETOOTH,
                        Manifest.permission.BLUETOOTH_ADMIN
                    )
                }
            }
            else -> if (feature.startsWith("android.permission.")) arrayOf(feature) else emptyArray()
        }
    }

    fun hasFeaturePermission(feature: String): Boolean {
        val perms = getPermissionsForFeature(feature)
        if (perms.isEmpty()) return true
        return hasPermissions(perms)
    }

    fun requestPermissions(permissions: Array<String>, callback: (Boolean) -> Unit) {
        if (permissions.isEmpty() || hasPermissions(permissions)) {
            callback(true)
            return
        }

        val code = requestCodeGenerator.getAndIncrement()
        pendingCallbacks[code] = callback
        ActivityCompat.requestPermissions(activity, permissions, code)
    }

    fun requestFeaturePermission(feature: String, callback: (Boolean) -> Unit) {
        val perms = getPermissionsForFeature(feature)
        if (perms.isEmpty()) {
            callback(true)
            return
        }
        requestPermissions(perms, callback)
    }

    fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ): Boolean {
        val callback = pendingCallbacks.remove(requestCode) ?: return false
        val allGranted = grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED }
        callback.invoke(allGranted)
        return true
    }
}
