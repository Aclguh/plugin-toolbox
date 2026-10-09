package com.plugintoolbox.plugin_toolbox

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class SensorHandler(private val context: Context) : FeatureHandler {
    private var sensorManager: SensorManager? = null
    private val sensorListeners = mutableMapOf<String, SensorEventListener>()
    private val latestSensorReadings = mutableMapOf<String, Map<String, Any>>()
    private val gravityValues = FloatArray(3)
    private val geomagneticValues = FloatArray(3)
    private var hasGravity = false
    private var hasGeomagnetic = false

    private fun getOrCreateSensorManager(): SensorManager {
        if (sensorManager == null) {
            sensorManager = context.getSystemService(Context.SENSOR_SERVICE) as SensorManager
        }
        return sensorManager!!
    }

    override fun handleMethodCall(call: MethodCall, result: MethodChannel.Result): Boolean {
        return when (call.method) {
            "startSensor" -> {
                val type = call.argument<String>("type") ?: ""
                val sm = getOrCreateSensorManager()
                when (type) {
                    "accelerometer" -> {
                        val sensor = sm.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
                        if (sensor == null) {
                            result.success(false)
                            return true
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
                            return true
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
                            return true
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
                            return true
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
                true
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
                true
            }
            "getSensorData" -> {
                val type = call.argument<String>("type") ?: "accelerometer"
                val data = latestSensorReadings[type]
                result.success(data)
                true
            }
            else -> false
        }
    }

    override fun onPause() {
        sensorManager?.let { sm ->
            sensorListeners.values.forEach { sm.unregisterListener(it) }
        }
    }
}
