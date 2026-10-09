package com.plugintoolbox.plugin_toolbox

import android.content.Intent
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

interface FeatureHandler {
    fun handleMethodCall(call: MethodCall, result: MethodChannel.Result): Boolean
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean = false
    fun onPause() {}
    fun onDestroy() {}
}
