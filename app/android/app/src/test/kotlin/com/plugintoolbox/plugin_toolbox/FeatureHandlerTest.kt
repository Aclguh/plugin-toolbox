package com.plugintoolbox.plugin_toolbox

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class FeatureHandlerTest {

    @Test
    fun testGenerateToneBufferCalculatesAccurateLength() {
        val sampleRate = 44100
        val durationMs = 100 // 100ms
        val freq = 440.0 // A4

        val buffer = MediaHandler.generateToneBuffer(freq, durationMs, sampleRate)
        val expectedSamples = durationMs * sampleRate / 1000 // 4410 samples

        assertEquals(expectedSamples, buffer.size)
        // Verify buffer is not all zeros
        var hasNonZero = false
        for (sample in buffer) {
            if (sample.toInt() != 0) {
                hasNonZero = true
                break
            }
        }
        assertTrue("Tone buffer should contain oscillating waveform samples", hasNonZero)
    }

    @Test
    fun testGenerateToneBufferZeroDurationProducesEmptyBuffer() {
        val buffer = MediaHandler.generateToneBuffer(440.0, 0, 44100)
        assertEquals(0, buffer.size)
    }

    @Test
    fun testPermissionHelperMapsFeaturesCorrectly() {
        val locationPerms = PermissionHelper.getPermissionsForFeature("location")
        assertEquals(2, locationPerms.size)
        assertTrue(locationPerms.contains("android.permission.ACCESS_FINE_LOCATION"))
        assertTrue(locationPerms.contains("android.permission.ACCESS_COARSE_LOCATION"))

        val audioPerms = PermissionHelper.getPermissionsForFeature("audio")
        assertEquals(1, audioPerms.size)
        assertEquals("android.permission.RECORD_AUDIO", audioPerms[0])

        val micPerms = PermissionHelper.getPermissionsForFeature("microphone")
        assertEquals(1, micPerms.size)
        assertEquals("android.permission.RECORD_AUDIO", micPerms[0])

        val cameraPerms = PermissionHelper.getPermissionsForFeature("camera")
        assertEquals(1, cameraPerms.size)
        assertEquals("android.permission.CAMERA", cameraPerms[0])
    }

    @Test
    fun testPermissionHelperHandlesVersionSpecificPermissions() {
        // Notification on Android 13 (API 33, Tiramisu) vs Android 12 (API 32)
        val notifPost33 = PermissionHelper.getPermissionsForFeature("notification", sdkInt = 33)
        assertEquals(1, notifPost33.size)
        assertEquals("android.permission.POST_NOTIFICATIONS", notifPost33[0])

        val notifPre33 = PermissionHelper.getPermissionsForFeature("notification", sdkInt = 32)
        assertEquals(0, notifPre33.size)

        // Bluetooth on Android 12 (API 31, S) vs Android 11 (API 30)
        val btS = PermissionHelper.getPermissionsForFeature("bluetooth", sdkInt = 31)
        assertEquals(2, btS.size)
        assertTrue(btS.contains("android.permission.BLUETOOTH_SCAN"))
        assertTrue(btS.contains("android.permission.BLUETOOTH_CONNECT"))

        val btPreS = PermissionHelper.getPermissionsForFeature("bluetooth", sdkInt = 30)
        assertEquals(2, btPreS.size)
        assertTrue(btPreS.contains("android.permission.BLUETOOTH"))
        assertTrue(btPreS.contains("android.permission.BLUETOOTH_ADMIN"))
    }

    @Test
    fun testPermissionHelperCustomAndUnknownFeatures() {
        val custom = PermissionHelper.getPermissionsForFeature("android.permission.VIBRATE")
        assertEquals(1, custom.size)
        assertEquals("android.permission.VIBRATE", custom[0])

        val unknown = PermissionHelper.getPermissionsForFeature("unknown_nonexistent_feat")
        assertEquals(0, unknown.size)
    }
}
