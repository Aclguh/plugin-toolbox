package com.plugintoolbox.plugin_toolbox

import android.content.Context
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.media.MediaPlayer
import android.media.MediaRecorder
import android.os.Build
import android.speech.tts.TextToSpeech
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.Locale

import android.app.Activity

class MediaHandler(
    private val context: Context,
    private val permissionHelper: PermissionHelper? = if (context is Activity) PermissionHelper(context) else null
) : FeatureHandler {
    private var activeMediaPlayer: MediaPlayer? = null
    private var activeMediaRecorder: MediaRecorder? = null
    private var recordingStartTime = 0L
    private var recordingFilePath: String? = null
    private var textToSpeech: TextToSpeech? = null
    private var ttsReady = false

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ): Boolean {
        return permissionHelper?.onRequestPermissionsResult(requestCode, permissions, grantResults) ?: false
    }

    override fun handleMethodCall(call: MethodCall, result: MethodChannel.Result): Boolean {
        return when (call.method) {
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
                true
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
                true
            }
            "playTone" -> {
                val freq = call.argument<Double>("frequency") ?: 440.0
                val duration = call.argument<Int>("durationMs") ?: 200
                Thread {
                    try {
                        val sampleRate = 44100
                        val buffer = generateToneBuffer(freq, duration, sampleRate)
                        val numSamples = buffer.size
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
                true
            }
            "startAudioRecording" -> {
                val destPath = call.argument<String>("path") ?: ""
                val doStart = {
                    try {
                        activeMediaRecorder?.release()
                        val recorder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                            MediaRecorder(context)
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

                if (permissionHelper != null && !permissionHelper.hasPermission(android.Manifest.permission.RECORD_AUDIO)) {
                    permissionHelper.requestPermissions(arrayOf(android.Manifest.permission.RECORD_AUDIO)) { granted ->
                        if (granted) {
                            doStart()
                        } else {
                            result.success(false)
                        }
                    }
                } else {
                    doStart()
                }
                true
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
                true
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
                true
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
                    textToSpeech = TextToSpeech(context) { status ->
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
                true
            }
            "stopSpeaking" -> {
                try {
                    textToSpeech?.stop()
                    result.success(true)
                } catch (e: Exception) {
                    result.success(false)
                }
                true
            }
            else -> false
        }
    }

    override fun onDestroy() {
        activeMediaPlayer?.release()
        activeMediaPlayer = null
        activeMediaRecorder?.let {
            try { it.stop() } catch (_: Exception) {}
            it.release()
        }
        activeMediaRecorder = null
        textToSpeech?.shutdown()
        textToSpeech = null
    }

    companion object {
        fun generateToneBuffer(freq: Double, durationMs: Int, sampleRate: Int = 44100): ShortArray {
            val numSamples = (durationMs * sampleRate / 1000)
            val buffer = ShortArray(numSamples)
            for (i in 0 until numSamples) {
                val angle = 2.0 * Math.PI * i * freq / sampleRate
                buffer[i] = (Math.sin(angle) * 32767).toInt().toShort()
            }
            return buffer
        }
    }
}
