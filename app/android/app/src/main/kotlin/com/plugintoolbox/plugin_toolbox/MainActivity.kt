package com.plugintoolbox.plugin_toolbox

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.plugintoolbox/host_native"

    // 初始分享数据接收
    private var initialShareData: Map<String, Any>? = null
    private val handlers = mutableListOf<FeatureHandler>()
    private val permissionHelper by lazy { PermissionHelper(this) }

    override fun onCreate(savedInstanceState: Bundle?) {
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

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        handlers.clear()
        handlers.add(SystemFeatureHandler(
            activity = this,
            permissionHelper = permissionHelper,
            getInitialShareData = { initialShareData },
            clearInitialShareData = { initialShareData = null }
        ))
        handlers.add(MediaHandler(this, permissionHelper))
        handlers.add(SensorHandler(this))
        handlers.add(ImageHandler(this))
        handlers.add(BarcodeHandler(this))

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            for (handler in handlers) {
                if (handler.handleMethodCall(call, result)) {
                    return@setMethodCallHandler
                }
            }
            result.notImplemented()
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (permissionHelper.onRequestPermissionsResult(requestCode, permissions, grantResults)) {
            return
        }
        for (handler in handlers) {
            if (handler.onRequestPermissionsResult(requestCode, permissions, grantResults)) {
                return
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        for (handler in handlers) {
            if (handler.onActivityResult(requestCode, resultCode, data)) {
                return
            }
        }
    }

    override fun onPause() {
        super.onPause()
        handlers.forEach { it.onPause() }
    }

    override fun onDestroy() {
        super.onDestroy()
        handlers.forEach { it.onDestroy() }
        handlers.clear()
    }
}
