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
}
