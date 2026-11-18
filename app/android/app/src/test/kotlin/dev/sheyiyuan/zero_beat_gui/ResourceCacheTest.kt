package dev.sheyiyuan.zero_beat_gui

import java.io.ByteArrayInputStream
import java.io.File
import java.io.IOException
import java.io.InputStream
import java.io.RandomAccessFile
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class ResourceCacheTest {
    @get:Rule val temp = TemporaryFolder()

    @Test fun stagesNonSeekableStreamWithUnknownLengthForRandomReads() {
        val bytes = ByteArray(200000) { (it % 251).toByte() }
        var closed = false
        val stream = object : ByteArrayInputStream(bytes) {
            override fun available() = 0
            override fun markSupported() = false
            override fun reset() { throw UnsupportedOperationException() }
            override fun close() { closed = true; super.close() }
        }
        val file = ResourceCache(temp.newFolder()).stage(stream)
        assertTrue(closed)
        assertEquals(bytes.size.toLong(), file.length())
        RandomAccessFile(file, "r").use {
            it.seek(150000)
            assertEquals(bytes[150000].toInt() and 255, it.read())
            it.seek(0)
            assertEquals(bytes[0].toInt() and 255, it.read())
        }
    }

    @Test fun readFailureClosesInputAndRemovesPartialFile() {
        val dir = temp.newFolder()
        var closed = false
        val stream = object : InputStream() {
            override fun read(): Int = throw IOException("provider unavailable")
            override fun close() { closed = true }
        }
        try {
            ResourceCache(dir).stage(stream)
            fail("must report provider failure")
        } catch (_: IOException) {}
        assertTrue(closed)
        assertEquals(0, dir.listFiles()!!.size)
    }

    @Test fun allocationFailureStillClosesInput() {
        val dir = temp.newFolder()
        val cache = ResourceCache(dir)
        assertTrue(dir.delete())
        var closed = false
        val stream = object : ByteArrayInputStream(byteArrayOf(1)) {
            override fun close() { closed = true; super.close() }
        }
        try {
            cache.stage(stream)
            fail("must report disk failure")
        } catch (_: IOException) {}
        assertTrue(closed)
    }

    @Test fun processRestartRemovesOrphansButSubsequentCopiesKeepLiveFiles() {
        val dir = temp.newFolder()
        val orphan = File(dir, "resource-old.media").apply { writeText("old") }
        val cache = ResourceCache(dir)
        assertFalse(orphan.exists())
        val first = cache.stage(ByteArrayInputStream(byteArrayOf(1)))
        val second = cache.stage(ByteArrayInputStream(byteArrayOf(2)))
        assertTrue(first.exists())
        assertTrue(second.exists())
        assertNotEquals(first, second)
    }
}
